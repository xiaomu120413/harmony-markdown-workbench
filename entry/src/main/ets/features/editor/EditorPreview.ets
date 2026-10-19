import { promptAction } from '@kit.ArkUI';
import { ViewModePolicy } from '../../domain/editor/ViewModePolicy';
import { HeadingOutline } from '../../domain/editor/HeadingOutline';
import { DocumentDeliveryService } from '../../services/DocumentDeliveryService';
import { DefaultView } from '../../domain/settings/AppSettings';
import { EditorController } from './EditorController';
import { OutlineEntry } from './EditorTypes';
const PREVIEW_SYNC_DEBOUNCE_MS = 300;
export class EditorPreview {
  private host: EditorController;
  constructor(host: EditorController) { this.host = host; }
  scheduleDocSync(): void {
    if (this.host.state.viewMode === DefaultView.EDIT && !this.host.state.outlineVisible) {
      return;
    }
    if (this.host.env.previewTimer >= 0) {
      clearTimeout(this.host.env.previewTimer);
    }
    this.host.env.previewTimer = setTimeout(() => {
      this.host.env.previewTimer = -1;
      this.host.syncDocNow();
    }, PREVIEW_SYNC_DEBOUNCE_MS);
  }

  syncDocNow(): void {
    if (!this.host.state.webReady) {
      return;
    }
    const needPreview = this.host.state.previewReady && this.host.state.viewMode !== DefaultView.EDIT;
    const needOutline = this.host.state.outlineVisible;
    if (!needPreview && !needOutline) {
      return;
    }
    this.host.runJsValue('window.__editorApi.getSnapshot();').then((md: string) => {
      if (needPreview && md !== this.host.state.lastPreviewedMd) {
        this.host.state.lastPreviewedMd = md;
        this.host.renderPreview(md, this.host.state.activeSession);
      }
      if (needOutline) {
        this.host.rebuildOutline(md);
      }
    });
  }

  async renderPreview(md: string, session: string): Promise<void> {
    try {
      const images = await this.host.inspectImages(md);
      const service = new DocumentDeliveryService(this.host.env.ctx);
      const resources: Record<string, string> = {};
      let total = 0;
      let incomplete = false;
      for (const source of images) {
        try {
          const item = service.resources([source]);
          for (const key of Object.keys(item)) {
            total += item[key].length;
            if (total > 28 * 1024 * 1024) { throw new Error('preview image limit'); }
            resources[key] = item[key];
          }
        } catch (e) { incomplete = true; }
      }
      if (!this.host.isActive() || session !== this.host.state.activeSession || md !== this.host.state.lastPreviewedMd) { return; }
      if (incomplete) { this.host.append('[预览] 部分图片无法读取或超过限额，正文及附件未修改'); }
      await this.host.runJsChecked(this.host.env.previewController,
        `window.__previewApi.render(${JSON.stringify(md)}, ${JSON.stringify(resources)});`);
    } catch (e) { this.host.append('[预览] 渲染失败，请重新切换预览视图'); }
  }

  rebuildOutline(md: string): void {
    const items = HeadingOutline.extract(md);
    const offsets = HeadingOutline.lineOffsets(md);
    const entries: OutlineEntry[] = [];
    for (let i = 0; i < items.length; i++) {
      const it = items[i];
      const from = it.line < offsets.length ? offsets[it.line] : 0;
      const to = it.line + 1 < offsets.length ? offsets[it.line + 1] - 1 : md.length;
      entries.push({
        level: it.level,
        text: it.text.length > 0 ? it.text : '（无标题）',
        from: from,
        to: to,
      });
    }
    this.host.state.outlineEntries = entries;
  }

  jumpToOutlineEntry(e: OutlineEntry): void {
    if (this.host.state.viewMode === DefaultView.PREVIEW) {
      this.host.setViewMode(DefaultView.EDIT);
    }
    this.host.runJsValue(`window.__editorApi.setSelectionRange(${e.from}, ${e.to});`);
  }

  toggleOutline(): void {
    if (this.host.state.bp === 'phone') {
      this.host.state.outlineVisible = false;
      if (this.host.state.fileSheetVisible && this.host.state.fileSheetSection === 'outline') { this.host.state.fileSheetVisible = false; }
      else { this.host.openPhoneOutline(); }
      return;
    }
    if (!this.host.state.outlineVisible && !ViewModePolicy.outlineFits(this.host.state.contentWidthVp, this.host.state.sidebarVisible)) {
      promptAction.showToast({ message: '空间不足，请先收起文档侧栏再打开大纲' });
      return;
    }
    this.host.state.outlineVisible = !this.host.state.outlineVisible;
    this.host.enforceWorkspaceBudget();
    if (this.host.state.outlineVisible) {
      this.host.syncDocNow();
    }
  }

  enforceWorkspaceBudget(): void {
    const sidebarOpen = this.host.state.sidebarVisible && this.host.state.bp !== 'phone';
    if (this.host.state.bp === 'phone' || (this.host.state.outlineVisible &&
      !ViewModePolicy.outlineFits(this.host.state.contentWidthVp, sidebarOpen))) {
      this.host.state.outlineVisible = false;
    }
    if (this.host.state.viewMode === DefaultView.SPLIT && (this.host.state.bp === 'phone' ||
      !ViewModePolicy.splitFits(this.host.state.contentWidthVp, sidebarOpen, this.host.state.outlineVisible))) {
      this.host.state.viewMode = DefaultView.EDIT;
    }
  }

  async openPhoneOutline(): Promise<void> {
    const session = this.host.state.activeSession;
    const md = await this.host.runJsValue('window.__editorApi.getSnapshot();');
    if (!this.host.isActive() || session !== this.host.state.activeSession || this.host.state.bp !== 'phone') { return; }
    this.host.rebuildOutline(md);
    this.host.state.fileSheetSection = 'outline';
    this.host.state.fileSheetVisible = true;
  }

  setViewMode(mode: DefaultView): void {
    if (mode === this.host.state.viewMode) {
      return;
    }
    if (mode === DefaultView.SPLIT && !ViewModePolicy.allowsSplit(this.host.state.bp)) {
      return;
    }
    // B4-01：分屏需满足空间预算（扣除侧栏+大纲后 ≥ 编辑+预览最小宽度）
    if (mode === DefaultView.SPLIT && !ViewModePolicy.splitFits(this.host.state.contentWidthVp, this.host.state.sidebarVisible, this.host.state.outlineVisible)) {
      promptAction.showToast({ message: '空间不足，无法分屏（请收起侧栏或大纲）' });
      return;
    }
    this.host.state.viewMode = mode;
    if (mode !== DefaultView.EDIT) {
      this.host.syncDocNow();
    }
  }
}
