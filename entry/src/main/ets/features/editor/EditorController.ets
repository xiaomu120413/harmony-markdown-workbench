import { common } from '@kit.AbilityKit';
import { EditorEnvironment } from './EditorEnvironment';
import { webview } from '@kit.ArkWeb';
import { MarkdownCommandName } from '../../domain/editor/MarkdownCommands';
import { FindOptions } from '../../domain/editor/FindReplaceEngine';
import { SnapshotData } from '../../services/SaveCoordinator';
import { DocumentSource, WriteDocumentResult } from '../../domain/document/DocumentFileAdapter';
import { DefaultView } from '../../domain/settings/AppSettings';
import { UIContext } from '@kit.ArkUI';
import { EditorState } from './EditorState';
import { OutlineEntry } from './EditorTypes';
import { EditorBridgeChannel } from './EditorBridgeChannel';
import { EditorLifecycle } from './EditorLifecycle';
import { EditorDocuments } from './EditorDocuments';
import { EditorPreview } from './EditorPreview';
import { EditorFind } from './EditorFind';
import { EditorPersistence } from './EditorPersistence';
import { EditorRuntime } from './EditorRuntime';
import { EditorDelivery } from './EditorDelivery';

/** Page-facing command facade; each collaborator owns one responsibility. */
export class EditorController {
  readonly channel = new EditorBridgeChannel();
  private lifecycle: EditorLifecycle;
  private documents: EditorDocuments;
  private preview: EditorPreview;
  private find: EditorFind;
  private persistence: EditorPersistence;
  private runtime: EditorRuntime;
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
    this.runtime = new EditorRuntime(this);
    this.delivery = new EditorDelivery(this);
  }
  isActive(): boolean { return this.state.pageActive && !this.env.disposed; }
  sendBridge(raw: string): void { if (this.isActive()) { this.channel.send(raw); } }
  append(line: string): void { return this.lifecycle.append(line); }
  onCheckpointRequest(): void { return this.lifecycle.onCheckpointRequest(); }
  aboutToAppear(): void { return this.lifecycle.aboutToAppear(); }
  applyAppSettings(): void { return this.lifecycle.applyAppSettings(); }
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
  fingerprintOf(target: DocumentSource): string { return this.persistence.fingerprintOf(target); }
  requestLeave(): Promise<void> { return this.persistence.requestLeave(); }
  goBack(): Promise<void> { return this.persistence.goBack(); }
  getSnapshotData(): Promise<SnapshotData> { return this.persistence.getSnapshotData(); }
  save(): Promise<void> { return this.persistence.save(); }
  conflictKeepDisk(): void { return this.persistence.conflictKeepDisk(); }
  conflictKeepLocal(): void { return this.persistence.conflictKeepLocal(); }
  conflictSaveCopy(): void { return this.persistence.conflictSaveCopy(); }
  openDocument(): Promise<void> { return this.persistence.openDocument(); }
  newDocument(): Promise<void> { return this.persistence.newDocument(); }
  runJsChecked(ctrl: webview.WebviewController, script: string): Promise<string> { return this.runtime.runJsChecked(ctrl, script); }
  runJsValue(script: string): Promise<string> { return this.runtime.runJsValue(script); }
  runJsValueOn(ctrl: webview.WebviewController, script: string): Promise<string> { return this.runtime.runJsValueOn(ctrl, script); }
  decodeReturn(result: string): string { return this.runtime.decodeReturn(result); }
  applyCommand(cmd: MarkdownCommandName): Promise<void> { return this.runtime.applyCommand(cmd); }
  applyHistory(kind: 'undo' | 'redo'): Promise<void> { return this.runtime.applyHistory(kind); }
  documentLocation(): string { return this.runtime.documentLocation(); }
  dismissFileSheet(action: () => void): void { return this.runtime.dismissFileSheet(action); }
  fileSheetClosed(): void { return this.runtime.fileSheetClosed(); }
  saveStatusColor(): string { return this.runtime.saveStatusColor(); }
  showLocation(): void { return this.runtime.showLocation(); }
  showHelp(): void { return this.runtime.showHelp(); }
  inspectImages(content: string): Promise<string[]> { return this.delivery.inspectImages(content); }
  renderForDelivery(content: string, resources: Record<string, string>): Promise<string> { return this.delivery.renderForDelivery(content, resources); }
  deliverDocument(action: number): Promise<void> { return this.delivery.deliverDocument(action); }
  insertLocalImage(): Promise<void> { return this.delivery.insertLocalImage(); }
}
