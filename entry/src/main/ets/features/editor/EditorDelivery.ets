import { MuLogger } from '../../common/MuLogger';
import { promptAction } from '@kit.ArkUI';
import { pasteboard, deviceInfo } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { picker, fileUri, fileIo as fs } from '@kit.CoreFileKit';
import { SaveState } from '../../domain/recovery/SaveStateMachine';
import { DocumentDeliveryService } from '../../services/DocumentDeliveryService';
import { ExternalSource, InternalSource } from '../../domain/document/DocumentFileAdapter';
import { HashUtil } from '../../domain/document/HashUtil';
import { EditorController } from './EditorController';
import { SafeFileIO } from '../../infrastructure/file/SafeFileIO';
import { HtmlResourceStore } from '../../infrastructure/file/HtmlResourceStore';
import { DocumentImportService } from '../../services/DocumentImportService';
export class EditorDelivery {
  private host: EditorController;
  constructor(host: EditorController) { this.host = host; }
  private isCurrent(session: string): boolean {
    return this.host.isActive() && session === this.host.env.activeSession;
  }
  /** 写回失败时清理刚复制/生成的附件；文档切换场景保留，避免旧会话已引用而断链。 */
  private removeAttachment(path: string): void {
    if (path.length === 0) { return; }
    const source: InternalSource = { kind: 'internal', relativePath: path };
    this.host.env.internal.remove(source);
  }
  private async htmlResources(id: string, html: string, session: string): Promise<Record<string, string>> {
    const source = fileUri.getUriFromPath(`${this.host.env.ctx.filesDir}/${id}`);
    const store = new HtmlResourceStore(source.substring(0, source.lastIndexOf('/')));
    const resources: Record<string, string> = {};
    for (let round = 0; round < 32; round++) {
      if (!this.isCurrent(session)) { throw new Error('文档已切换，已取消插入'); }
      const paths = JSON.parse(await this.host.runJsChecked(this.host.env.controller,
        `window.__editorApi.inspectHtml(${JSON.stringify(html)}, ${JSON.stringify(resources)});`)) as string[];
      let loaded = 0;
      let missing = 0;
      for (const path of paths) {
        if (resources[path] !== undefined) { continue; }
        try {
          const item = store.read(HtmlResourceStore.BASE + encodeURI(path));
          resources[path] = `data:${item.mime};base64,${new util.Base64Helper().encodeToStringSync(item.bytes)}`;
          loaded++;
        } catch (e) {
          const message = String(e).replace(/^(Error: )+/, '');
          if (/^(资源超过|文件超过本次操作的大小限制|不导入符号链接|资源路径)/.test(message)) { throw new Error(message); }
          missing++;
        }
      }
      if (loaded > 0) { continue; } // 新导入 CSS 后再解析其 @import 和图片。
      if (missing === 0) { return resources; }
      // 手机可能声明系统能力却忽略 FOLDER；已验证平板和 2in1 可选目录。
      const choice: promptAction.ActionMenuSuccessResponse =
        (deviceInfo.deviceType === 'tablet' || deviceInfo.deviceType === '2in1') &&
        canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection')
        ? await promptAction.showActionMenu({ title: `HTML 还缺少 ${missing} 个图片或样式资源`, buttons: [
        { text: '选择 HTML 所在目录', color: this.host.state.pal.TEXT },
        { text: '选择图片和 CSS 文件', color: this.host.state.pal.TEXT },
      ] }) : { index: 1 };
      if (!this.isCurrent(session)) { throw new Error('文档已切换，已取消插入'); }
      const viewPicker = new picker.DocumentViewPicker(this.host.env.ctx);
      const uris = choice.index === 0
        ? await viewPicker.select({ maxSelectNumber: 1, selectMode: picker.DocumentSelectMode.FOLDER })
        : await viewPicker.select({ maxSelectNumber: 128, fileSuffixFilters: ['.css', '.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.bmp', '.ico', '.avif'] });
      if (!this.isCurrent(session) || uris.length === 0) { throw new Error('已取消插入 HTML，正文未改动'); }
      if (choice.index === 0) { store.useFolder(uris[0]); } else { store.importFiles(uris); }
    }
    throw new Error('HTML 资源引用过深或未补齐，请整理资源后重试');
  }

  async insertHtml(id?: string): Promise<void> {
    if (!this.host.isActive() || this.host.state.deliveryBusy || this.host.state.loadState !== 'ready') { return; }
    const session = this.host.env.activeSession;
    this.host.state.deliveryBusy = true;
    let attachmentPath = '';
    try {
      await this.host.runJsChecked(this.host.env.controller, 'window.__editorApi.setEditable(false);', true);
      if (id === undefined) {
        const uris = await new picker.DocumentViewPicker(this.host.env.ctx).select({ maxSelectNumber: 1, fileSuffixFilters: ['.html', '.htm'] });
        if (!this.isCurrent(session) || uris.length === 0) { return; }
        id = await new DocumentImportService(this.host.env.ctx).importUri(uris[0]);
      }
      if (!this.isCurrent(session)) { return; }
      const read = await this.host.env.internal.read({ kind: 'internal', relativePath: id });
      if (!read.validUtf8 || read.revision.size > 8 * 1024 * 1024) { throw new Error('仅支持 8 MiB 以内的 UTF-8 HTML'); }
      const resources = await this.htmlResources(id, read.content, session);
      const html = await this.host.runJsChecked(this.host.env.controller,
        `window.__editorApi.bundleHtml(${JSON.stringify(read.content)}, ${JSON.stringify(resources)});`);
      if (!this.isCurrent(session)) { return; }
      const bytes = util.TextEncoder.create('utf-8').encodeInto(html);
      if (bytes.byteLength > 12 * 1024 * 1024) { throw new Error('内嵌 HTML 超过 12 MiB，请缩小图片后插入'); }
      const folder = `${this.host.env.ctx.filesDir}/attachments`;
      if (!fs.accessSync(folder)) { fs.mkdirSync(folder); }
      const name = `html-${Date.now()}-${Math.floor(Math.random() * 0xffffff)}.html`;
      attachmentPath = `attachments/${name}`;
      SafeFileIO.atomicBytes(`${folder}/${name}`, bytes);
      const inserted = await this.insertAttachment(attachmentPath, 'HTML', session);
      if (inserted && this.isCurrent(session)) {
        attachmentPath = '';
        promptAction.showToast({ message: 'HTML 已插入光标处，可切换预览查看' });
      }
    } catch (e) {
      this.removeAttachment(attachmentPath);
      attachmentPath = '';
      MuLogger.warn('HTML insertion incomplete');
      const error: ESObject = e as ESObject;
      if (this.isCurrent(session) && error.code !== 1006 && error.code !== 1007) {
        promptAction.showToast({ message: String(e).replace(/^Error: /, '') });
      }
    } finally {
      if (this.host.isActive()) { this.host.state.deliveryBusy = false; }
      if (this.isCurrent(session)) {
        this.host.runJsChecked(this.host.env.controller, 'window.__editorApi.setEditable(true);', true).catch(() => {
          MuLogger.warn('HTML insertion editor restore failed');
        });
      }
      if (this.host.isActive() && this.host.env.pendingOpenUri.length > 0) { this.host.onExternalOpen(); }
    }
  }

  async insertAttachment(path: string, label: string, session: string): Promise<boolean> {
    const raw = await this.host.runJsChecked(this.host.env.controller, 'window.__editorApi.getSelectionRange();');
    if (!this.isCurrent(session)) { return false; }
    const selection: ESObject = JSON.parse(raw);
    const at = selection.from as number;
    if (typeof at !== 'number' || !Number.isInteger(at) || at < 0) { throw new Error('无法获取插入位置，请重新定位光标'); }
    const snippet = label === 'HTML' ? `\n\n![HTML](<${path}>)\n\n` : `![图片](<${path}>)`;
    await this.host.runJsChecked(this.host.env.controller,
      `window.__editorApi.replaceRange(${at}, ${at}, ${JSON.stringify(snippet)});`, true);
    if (!this.isCurrent(session)) { return false; }
    // 写回成功后才推进保存状态；失败时调用方不得提示成功。
    this.host.env.coordinator?.onEdit(Date.now());
    this.host.state.saveState = this.host.env.coordinator?.state ?? SaveState.DIRTY;
    this.host.scheduleDocSync();
    return true;
  }
  async inspectImages(content: string): Promise<string[]> {
    const raw = await this.host.runJsChecked(this.host.env.controller,
      `window.__editorApi.inspectMarkdown(${JSON.stringify(content)});`);
    const parsed: ESObject = JSON.parse(raw);
    return parsed.images as string[];
  }

  async renderForDelivery(content: string, resources: Record<string, string>): Promise<string> {
    return this.host.runJsChecked(this.host.env.controller,
      `window.__editorApi.renderMarkdown(${JSON.stringify(content)}, ${JSON.stringify(resources)});`);
  }

  async deliverDocument(action: number): Promise<void> {
    const c = this.host.env.coordinator;
    if (!this.host.isActive() || this.host.state.deliveryBusy || c === undefined || this.host.state.loadState !== 'ready') { return; }
    if (c.state === SaveState.SAVING) {
      promptAction.showToast({ message: '正在保存，请完成后再导出或另存' }); return;
    }
    this.host.state.deliveryBusy = true;
    const session = this.host.env.activeSession;
    try {
      // 阻止选择器期间改写正文；取消后恢复编辑和原保存目标。
      await this.host.runJsChecked(this.host.env.controller, 'window.__editorApi.setEditable(false);', true);
      if (!this.isCurrent(session)) { return; }
      const snap = await this.host.getSnapshotData();
      if (!this.isCurrent(session)) { return; }
      if (!snap.ok || session !== snap.sessionId) { throw new Error('获取正文失败，请重试'); }
      if (!await c.checkpointNow()) { throw new Error('恢复草稿写入失败，请先检查可用空间'); }
      if (!this.isCurrent(session)) { return; }
      const service = new DocumentDeliveryService(this.host.env.ctx);
      const images = await this.host.inspectImages(snap.content);
      if (!this.isCurrent(session)) { return; }
      if ((action === 0 || action === 1) && images.length > 0) {
        // 单文件 Markdown 不能携带附件；用户显式选定后才输出正文副本。
        const accepted = await new Promise<boolean>((resolve) => {
          AlertDialog.show({ title: 'Markdown 文件不包含附件',
            message: '此操作仅保存 Markdown 正文。要把图片及 HTML 内容块一起带走，请取消并选择“导出图文 ZIP”。',
            primaryButton: { value: '仅保存正文', action: () => resolve(true) },
            secondaryButton: { value: '取消', action: () => resolve(false) }, cancel: () => resolve(false) });
        });
        if (!accepted || !this.isCurrent(session)) { return; }
      }
      if (action === 4 || action === 7) {
        const payload = action === 4 ? snap.content : await this.host.renderForDelivery(snap.content, service.resources(images));
        if (!this.isCurrent(session)) { return; }
        await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, payload));
        promptAction.showToast({ message: action === 4 ? '已复制 Markdown 原文' : '已复制渲染 HTML' });
        return;
      }
      const result = action === 0 || action === 1
        ? await service.markdown(this.host.state.docTitle, snap.content)
        : action === 2 ? await service.zip(this.host.state.docTitle, snap.content, images)
          : await service.html(this.host.state.docTitle, snap.content, images,
            (text: string, resources: Record<string, string>) => this.host.renderForDelivery(text, resources));
      if (result === undefined) { return; }
      if (!this.host.isActive() || session !== this.host.env.activeSession) { return; }
      if (action === 0) {
        // 成功后才切换目标；后续 Ctrl+S 和自动保存都写入此文件。
        const previousDraftId = this.host.state.docTarget === undefined ? this.host.env.sessionDraftId : this.host.draftIdOf(this.host.state.docTarget);
        const source: ExternalSource = { kind: 'external', uri: result.uri, displayName: result.fileName };
        this.host.state.docTarget = source;
        this.host.state.docTitle = result.fileName;
        this.host.env.expectedRevision = { size: util.TextEncoder.create('utf-8').encodeInto(snap.content).byteLength,
          contentHash: HashUtil.of(snap.content) };
        this.host.env.docFormat = { encoding: 'utf-8', lineEnding: 'lf' };
        this.host.env.docValidUtf8 = true;
        this.host.env.coordinator = this.host.createSaveCoordinator();
        this.host.env.coordinator.onDocumentLoaded(session, snap.version);
        this.host.env.drafts.remove(previousDraftId);
        this.host.env.drafts.remove(this.host.env.sessionDraftId);
        this.host.state.recoveryLabel = '';
        this.host.state.saveState = SaveState.CLEAN;
        await this.host.env.external.retainAccess(source);
        if (!this.isCurrent(session)) { return; }
        await this.host.trackRecent(source);
        this.host.refreshSidebarData();
      }
      MuLogger.info(`[交付] ${action === 0 ? '保存目标已切换' : '副本导出完成'}`);
      promptAction.showToast({ message: `${action === 0 ? '已另存，后续保存使用新文件' : '已导出'}${result.remoteImages ? '；网络图片仍需联网查看' : ''}` });
    } catch (e) {
      if (!this.isCurrent(session)) { return; }
      MuLogger.info('[交付] 操作失败，原会话及草稿保留');
      AlertDialog.show({ title: '文件操作未完成', message: String(e), confirm: { value: '返回编辑', action: () => {} } });
    } finally {
      if (this.host.isActive()) { this.host.state.deliveryBusy = false; }
      if (this.host.isActive() && this.host.env.pendingOpenUri.length > 0) { this.host.onExternalOpen(); }
      if (this.isCurrent(session)) {
        this.host.runJsChecked(this.host.env.controller, 'window.__editorApi.setEditable(true);', true).catch(() => {
          MuLogger.info('[交付] 恢复编辑失败，请保留草稿后重新打开');
        });
      }
    }
  }

  async insertLocalImage(): Promise<void> {
    if (!this.host.isActive() || this.host.state.deliveryBusy) { return; }
    const session = this.host.env.activeSession;
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1,
      });
      const uris: Array<string> = result.photoUris;
      if (!this.isCurrent(session) || uris.length === 0) {
        return; // 用户取消
      }
      const uri = uris[0];
      // 从 URI 提取文件名（兜底 attachment.png）
      const slash = uri.lastIndexOf('/');
      let name = slash >= 0 ? uri.substring(slash + 1) : 'attachment.png';
      if (name.length === 0 || !name.includes('.')) {
        name = 'attachment.png';
      }
      // 复制到附件目录（应用私有，不依赖外部授权持久性）
      const attPath = this.host.env.internal.copyToAttachments(uri, name);
      if (attPath.length === 0) {
        promptAction.showToast({ message: '图片复制失败' });
        return;
      }
      let inserted = false;
      try {
        inserted = await this.insertAttachment(attPath, '图片', session);
      } catch (e) {
        const err: ESObject = e as ESObject;
        MuLogger.info(`[图片] 插入失败：${JSON.stringify(err)}`);
        this.removeAttachment(attPath);
        if (this.isCurrent(session)) { promptAction.showToast({ message: '图片插入失败，请重试' }); }
        return;
      }
      if (inserted && this.isCurrent(session)) {
        promptAction.showToast({ message: `已插入 ${name}` });
      }
    } catch (e) {
      const err: ESObject = e as ESObject;
      MuLogger.info(`[图片] 选择失败：${JSON.stringify(err)}`);
    }
  }
}
