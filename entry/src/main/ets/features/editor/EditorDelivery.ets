import { MuLogger } from '../../common/MuLogger';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { picker } from '@kit.CoreFileKit';
import { SaveState } from '../../domain/recovery/SaveStateMachine';
import { DocumentDeliveryService } from '../../services/DocumentDeliveryService';
import { ExternalSource } from '../../domain/document/DocumentFileAdapter';
import { HashUtil } from '../../domain/document/HashUtil';
import { EditorController } from './EditorController';
export class EditorDelivery {
  private host: EditorController;
  constructor(host: EditorController) { this.host = host; }
  private isCurrent(session: string): boolean {
    return this.host.isActive() && session === this.host.env.activeSession;
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
      await this.host.runJsChecked(this.host.env.controller, 'window.__editorApi.setEditable(false);');
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
          AlertDialog.show({ title: 'Markdown 文件不包含图片附件',
            message: '此操作仅保存 Markdown 正文。要把图片一起带走，请取消并选择“导出图文 ZIP”。',
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
        this.host.runJsChecked(this.host.env.controller, 'window.__editorApi.setEditable(true);').catch(() => {
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
      // 在光标处插入 Markdown 引用（相对路径，可迁移）
      const sel = await this.host.runJsValue('window.__editorApi.getSelectionRange();');
      if (!this.isCurrent(session)) { return; }
      let parsed: ESObject;
      try {
        parsed = JSON.parse(sel);
      } catch (e) {
        parsed = { from: 0, to: 0 };
      }
      const at = (parsed.from as number) ?? 0;
      const snippet = `![图片](<${attPath}>)`;
      await this.host.runJsValue(`window.__editorApi.replaceRange(${at}, ${at}, ${JSON.stringify(snippet)});`);
      const c = this.host.env.coordinator;
      if (c !== undefined) {
        c.onEdit(Date.now());
        this.host.state.saveState = c.state;
      }
      this.host.scheduleDocSync();
      promptAction.showToast({ message: `已插入 ${name}` });
    } catch (e) {
      const err: ESObject = e as ESObject;
      MuLogger.info(`[图片] 选择失败：${JSON.stringify(err)}`);
    }
  }
}
