import { MuLogger } from '../../common/MuLogger';
import { router } from '@kit.ArkUI';
import { RecentFileList } from '../../domain/document/RecentFileList';
import { common } from '@kit.AbilityKit';
import { EditorEnvironment } from './EditorEnvironment';
import { webview } from '@kit.ArkWeb';
import { MarkdownCommands, MarkdownCommandName, TextRange, TextTransformResult } from '../../domain/editor/MarkdownCommands';
import { FindOptions } from '../../domain/editor/FindReplaceEngine';
import { SaveCoordinator, SaveCoordinatorDeps, SnapshotData } from '../../services/SaveCoordinator';
import { DocumentSource, WriteDocumentResult } from '../../domain/document/DocumentFileAdapter';
import { DefaultView } from '../../domain/settings/AppSettings';
import { UIContext } from '@kit.ArkUI';
import { EditorState, OutlineEntry } from './EditorState';
import { EditorLifecycle } from './EditorLifecycle';
import { EditorDocuments } from './EditorDocuments';
import { EditorPreview } from './EditorPreview';
import { EditorFind } from './EditorFind';
import { EditorPersistence } from './EditorPersistence';
import { EditorDelivery } from './EditorDelivery';

/** Page-facing command facade; each collaborator owns one responsibility. */
export class EditorController {
  private lifecycle: EditorLifecycle;
  private documents: EditorDocuments;
  private preview: EditorPreview;
  private find: EditorFind;
  private persistence: EditorPersistence;
  private delivery: EditorDelivery;
  env: EditorEnvironment;
  state: EditorState;
  uiContext: UIContext;
  constructor(state: EditorState, uiContext: UIContext, ctx: common.UIAbilityContext) {
    this.state = state; this.uiContext = uiContext; this.env = new EditorEnvironment(ctx);
    this.lifecycle = new EditorLifecycle(this);
    this.documents = new EditorDocuments(this);
    this.preview = new EditorPreview(this);
    this.find = new EditorFind(this);
    this.persistence = new EditorPersistence(this);
    this.delivery = new EditorDelivery(this);
  }
  createSaveCoordinator(): SaveCoordinator {
    const deps: SaveCoordinatorDeps = {
      getSnapshot: () => this.getSnapshotData(),
      saveCheckpoint: (content: string) => this.doSaveCheckpoint(content),
      persist: (content: string) => this.doPersist(content),
      clearCheckpoint: () => this.clearSavedDrafts(),
    };
    return new SaveCoordinator(deps);
  }
  isActive(): boolean { return !this.env.disposed; }
  sendBridge(raw: string): void { if (this.isActive()) { this.env.bridgeMessages.push(raw); } }
  onCheckpointRequest(): void { return this.lifecycle.onCheckpointRequest(); }
  aboutToAppear(): void { return this.lifecycle.aboutToAppear(); }
  applyAppSettings(preserveView: boolean = false): void { return this.lifecycle.applyAppSettings(preserveView); }
  applyEditorStyle(): void { return this.lifecycle.applyEditorStyle(); }
  applyPreviewStyle(): void { return this.lifecycle.applyPreviewStyle(); }
  initSidebar(): void { return this.lifecycle.initSidebar(); }
  refreshSidebarData(): void { return this.lifecycle.refreshSidebarData(); }
  toggleSidebar(): void { return this.lifecycle.toggleSidebar(); }
  aboutToDisappear(): void { return this.lifecycle.aboutToDisappear(); }
  protectDraft(): Promise<boolean> { return this.documents.protectDraft(); }
  onExternalOpen(): Promise<void> { return this.documents.onExternalOpen(); }
  openReceivedDocument(id: string): void { return this.documents.openReceivedDocument(id); }
  receiveDrop(event: DragEvent): Promise<void> { return this.documents.receiveDrop(event); }
  insertHtml(id?: string): Promise<void> { return this.delivery.insertHtml(id); }
  switchToDocument(docId: string): Promise<void> { return this.documents.switchToDocument(docId); }
  resolveRouteParams(): void { return this.documents.resolveRouteParams(); }
  loadOpenedDoc(target: DocumentSource): void { return this.documents.loadOpenedDoc(target); }
  reselectExternalFile(): Promise<void> { return this.documents.reselectExternalFile(); }
  trackRecent(target: DocumentSource): Promise<void> { return this.documents.trackRecent(target); }
  flushPendingLoad(): void { return this.documents.flushPendingLoad(); }
  scheduleDocSync(): void { return this.preview.scheduleDocSync(); }
  syncDocNow(): void { return this.preview.syncDocNow(); }
  renderPreview(md: string, session: string): Promise<void> { return this.preview.renderPreview(md, session); }
  rebuildOutline(md: string): void { return this.preview.rebuildOutline(md); }
  jumpToOutlineEntry(e: OutlineEntry): void { return this.preview.jumpToOutlineEntry(e); }
  toggleOutline(): void { return this.preview.toggleOutline(); }
  enforceWorkspaceBudget(): void { return this.preview.enforceWorkspaceBudget(); }
  openPhoneOutline(): Promise<void> { return this.preview.openPhoneOutline(); }
  setViewMode(mode: DefaultView): void { return this.preview.setViewMode(mode); }
  findOpts(): FindOptions { return this.find.findOpts(); }
  openFind(): void { return this.find.openFind(); }
  refreshFind(): Promise<void> { return this.find.refreshFind(); }
  updateFindMatches(text: string): void { return this.find.updateFindMatches(text); }
  jumpNext(): void { return this.find.jumpNext(); }
  locateFirstMatch(): void { return this.find.locateFirstMatch(); }
  jumpPrev(): void { return this.find.jumpPrev(); }
  selectCurrentMatch(): void { return this.find.selectCurrentMatch(); }
  replaceCurrent(): Promise<void> { return this.find.replaceCurrent(); }
  replaceAllMatches(): Promise<void> { return this.find.replaceAllMatches(); }
  markEdited(): void { return this.find.markEdited(); }
  doSaveCheckpoint(content: string): Promise<void> { return this.persistence.doSaveCheckpoint(content); }
  doPersist(content: string): Promise<WriteDocumentResult> { return this.persistence.doPersist(content); }
  clearSavedDrafts(): Promise<void> { return this.persistence.clearSavedDrafts(); }
  draftIdOf(target: DocumentSource): string { return this.persistence.draftIdOf(target); }
  requestLeave(): Promise<void> { return this.persistence.requestLeave(); }
  goBack(): Promise<void> { return this.persistence.goBack(); }
  getSnapshotData(): Promise<SnapshotData> { return this.persistence.getSnapshotData(); }
  save(): Promise<void> { return this.persistence.save(); }
  conflictKeepDisk(): void { return this.persistence.conflictKeepDisk(); }
  conflictKeepLocal(): void { return this.persistence.conflictKeepLocal(); }
  conflictSaveCopy(): void { return this.persistence.conflictSaveCopy(); }
  openDocument(): Promise<void> { return this.persistence.openDocument(); }
  newDocument(): Promise<void> { return this.persistence.newDocument(); }
  inspectImages(content: string): Promise<string[]> { return this.delivery.inspectImages(content); }
  renderForDelivery(content: string, resources: Record<string, string>): Promise<string> { return this.delivery.renderForDelivery(content, resources); }
  deliverDocument(action: number): Promise<void> { return this.delivery.deliverDocument(action); }
  insertLocalImage(): Promise<void> { return this.delivery.insertLocalImage(); }
  /**
   * 带超时与错误校验的 JS 通道。读取默认不允许 undefined（读失败必须中止）；
   * 写命令（setDocument/replaceRange 等）返回 undefined 是正常结果，传 allowEmpty。
   */
  runJsChecked(ctrl: webview.WebviewController, script: string, allowEmpty: boolean = false): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('编辑器响应超时')), 5000);
      try {
        ctrl.runJavaScript(script, (err, result) => {
          clearTimeout(timer);
          if (err) { reject(new Error('编辑器调用失败')); }
          else if (result === undefined) {
            if (allowEmpty) { resolve(''); } else { reject(new Error('编辑器读取失败')); }
          } else { resolve(this.decodeReturn(result)); }
        });
      } catch (e) { clearTimeout(timer); reject(new Error('编辑器暂不可用')); }
    });
  }

  runJsValue(script: string): Promise<string> {
    return new Promise<string>((resolve) => {
      try {
        this.env.controller.runJavaScript(script, (err, result) => {
          resolve(err ? '' : (result === undefined ? '' : this.decodeReturn(result)));
        });
      } catch (e) {
        resolve('');
      }
    });
  }

  decodeReturn(result: string): string {
    const trimmed = result.trim();
    if (trimmed.length === 0 || trimmed.charAt(0) !== '"') {
      return result;
    }
    try {
      const v: ESObject = JSON.parse(trimmed);
      return v as string;
    } catch (e) {
      return result;
    }
  }

  async applyCommand(cmd: MarkdownCommandName): Promise<void> {
    if (this.state.deliveryBusy) { return; }
    const session = this.env.activeSession;
    try {
      // 读取失败必须中止：空字符串会被当成全文，setDocument 将覆盖整篇正文。
      const ctrl = this.env.controller;
      const selRaw = await this.runJsChecked(ctrl, 'window.__editorApi.getSelectionRange();');
      const text = await this.runJsChecked(ctrl, 'window.__editorApi.getSnapshot();');
      if (!this.isActive() || session !== this.env.activeSession) { return; }
      const parsed: ESObject = JSON.parse(selRaw);
      const range: TextRange = { from: parsed.from as number, to: parsed.to as number };
      if (typeof range.from !== 'number' || typeof range.to !== 'number' || !Number.isInteger(range.from) ||
        !Number.isInteger(range.to) || range.from < 0 || range.to < range.from || range.to > text.length) {
        throw new Error('选区无效');
      }
      const result: TextTransformResult = MarkdownCommands.apply(text, range, cmd);
      const js = `window.__editorApi.setDocument(${JSON.stringify(result.text)}, ${result.selection.from}, ${result.selection.to});`;
      await this.runJsChecked(ctrl, js, true);
      if (!this.isActive() || session !== this.env.activeSession) { return; }
      this.state.docLength = result.text.length;
      this.markEdited();
    } catch (e) {
      MuLogger.info(`[命令] ${cmd} 失败：${JSON.stringify(e)}`);
    }
  }

  async applyHistory(kind: 'undo' | 'redo'): Promise<void> {
    if (this.state.deliveryBusy) { return; }
    const len = await this.runJsValue(`window.__editorApi.${kind}();`);
    if (len.length > 0) {
      const n = Number(len);
      if (!Number.isNaN(n)) {
        this.state.docLength = n;
      }
    }
  }

  documentLocation(): string {
    const target = this.state.docTarget;
    return target === undefined ? '尚未保存到文件' : target.kind === 'internal'
      ? '我的文档 · 应用内' : RecentFileList.location(target.uri);
  }

  dismissFileSheet(action: () => void): void {
    this.env.afterFileSheet = action;
    this.state.fileSheetVisible = false;
  }

  fileSheetClosed(): void {
    this.state.fileSheetVisible = false;
    const action = this.env.afterFileSheet;
    this.env.afterFileSheet = undefined;
    if (this.isActive() && action !== undefined) { action(); }
  }

  saveStatusColor(): string {
    return this.state.saveLabel === '已保存' ? this.state.pal.TEXT_SUB
      : this.state.saveLabel === '外部冲突' || this.state.saveLabel === '保存失败' ? this.state.pal.DANGER : this.state.pal.AMBER;
  }

  async showLocation(): Promise<void> {
    const source = this.state.docTarget;
    const persistent = source?.kind === 'external' ? await this.env.external.canPersistAccess(source) : false;
    if (!this.isActive() || source !== this.state.docTarget) { return; }
    AlertDialog.show({ title: '当前保存位置', message: source === undefined
      ? '尚未保存到文件；恢复草稿仅在本机应用内保留。'
      : source.kind === 'internal'
        ? `我的文档 / ${source.relativePath.substring('library/'.length)}\n应用私有目录，卸载前请导出文档和附件。`
        : `外部原文件\n${source.uri}\n${persistent ? '已保留此文件的访问授权；移动文件或撤销授权后需重新选择。' : '临时访问授权；重启后可能需要重新选择文件。'}`,
      confirm: { value: '知道了', action: () => {} } });
  }

  showSettings(): void {
    router.pushUrl({ url: 'pages/SettingsPage' });
  }
}
