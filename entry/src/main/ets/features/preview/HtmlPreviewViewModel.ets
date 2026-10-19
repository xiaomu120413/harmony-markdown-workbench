import { common } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { MuLogger } from '../../common/MuLogger';
import { AppTheme } from '../../common/AppTheme';
import { DocumentIntake, DocumentOpenParams } from '../../domain/document/DocumentIntake';
import { RecentFileList } from '../../domain/document/RecentFileList';
import { InternalFileSource } from '../../infrastructure/file/InternalFileSource';
import { ExternalUriFileSource } from '../../infrastructure/file/ExternalUriFileSource';
import { MetadataStore } from '../../infrastructure/metadata/MetadataStore';
import { SettingsStore } from '../../infrastructure/metadata/SettingsStore';
import { ThemeMode } from '../../domain/settings/AppSettings';
import { DocumentImportService } from '../../services/DocumentImportService';

@Observed
export class HtmlPreviewState {
  title: string = 'HTML 预览';
  status: string = '正在读取 HTML…';
  pal: AppTheme = AppTheme.of(false);
}

/** 独立只读 Web；不创建编辑会话、SaveCoordinator 或 JSBridge。 */
export class HtmlPreviewViewModel {
  private active: boolean = true;
  private attached: boolean = false;
  private content: string = '';
  private importing: boolean = false;
  private state: HtmlPreviewState;
  private ctx: common.UIAbilityContext;
  private controller: webview.WebviewController;
  constructor(state: HtmlPreviewState, ctx: common.UIAbilityContext, controller: webview.WebviewController) {
    this.state = state; this.ctx = ctx; this.controller = controller;
  }

  static document(html: string): string {
    const policy = "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src data:; " +
      "frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'";
    // CSP 在不可信正文前生效；文档内的 meta 不能放宽已有策略。
    return '<!DOCTYPE html><html><head><meta charset="utf-8">' +
      `<meta http-equiv="Content-Security-Policy" content="${policy}">` +
      '<meta name="viewport" content="width=device-width, initial-scale=1">' +
      '<style>body{overflow-wrap:anywhere}img,table{max-width:100%}</style></head><body>' + html + '</body></html>';
  }

  async load(params: DocumentOpenParams): Promise<void> {
    try {
      const id = params.name ?? params.uri ?? '';
      if (!DocumentIntake.isHtml(id)) { throw new Error('请选择 HTML 文件'); }
      this.state.title = RecentFileList.displayName(id);
      const read = params.name !== undefined
        ? await new InternalFileSource(this.ctx).read({ kind: 'internal', relativePath: id })
        : await new ExternalUriFileSource().read({ kind: 'external', uri: id, displayName: this.state.title });
      if (!this.active) { return; }
      if (!read.validUtf8) { throw new Error('目前仅支持 UTF-8 HTML 文件'); }
      if (read.revision.size > 8 * 1024 * 1024) { throw new Error('HTML 内容超过 8 MB 预览限制'); }
      this.content = HtmlPreviewViewModel.document(read.content);
      this.show();
      this.state.status = '只读预览 · 脚本与联网已禁用';
      try {
        const meta = new MetadataStore(this.ctx);
        const recent = new RecentFileList(await meta.loadRecent());
        recent.touch(id, Date.now());
        await meta.saveRecent(recent.snapshot());
      } catch (e) { MuLogger.warn('HTML recent history update failed'); }
    } catch (e) {
      if (this.active) { this.state.status = `无法预览：${String(e).replace(/^Error: /, '')}`; }
      MuLogger.warn('HTML preview failed');
    }
  }

  attach(): void { if (!this.attached) { this.attached = true; this.show(); } }
  private show(): void {
    if (this.active && this.attached && this.content.length > 0) {
      this.controller.loadData(this.content, 'text/html', 'utf-8', 'https://mumark.invalid/');
    }
  }
  async loadTheme(): Promise<void> {
    const settings = await new SettingsStore(this.ctx).load();
    if (this.active) { this.state.pal = AppTheme.of(settings.theme === ThemeMode.DARK); }
  }
  async receiveDrop(event: DragEvent, cancel: (key: string) => void): Promise<void> {
    if (this.importing || !this.active) { return; }
    this.importing = true;
    try {
      const id = await new DocumentImportService(this.ctx, cancel).receive(event);
      if (this.active) { await router.replaceUrl({ url: DocumentIntake.page(id), params: DocumentIntake.route(id) }); }
    } catch (e) {
      MuLogger.warn('HTML preview drop failed');
      if (this.active) { promptAction.showToast({ message: String(e).replace(/^Error: /, '') }); }
    } finally { this.importing = false; }
  }
  dispose(): void { this.active = false; this.content = ''; }
}
