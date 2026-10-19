import { router, promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { SaveState, SaveStateMachine } from '../../domain/recovery/SaveStateMachine';
import { DocumentImportService } from '../../services/DocumentImportService';
import { DocumentIntake } from '../../domain/document/DocumentIntake';
import { SaveCoordinator } from '../../services/SaveCoordinator';
import { DocumentFileAdapter, DocumentSource, InternalSource, ExternalSource } from '../../domain/document/DocumentFileAdapter';
import { RecentFileList } from '../../domain/document/RecentFileList';
import { EditorController } from './EditorController';
import { EditorPageDeps } from './EditorPageDeps';
export class EditorDocuments {
  private host: EditorController;
  constructor(host: EditorController) { this.host = host; }
  async protectDraft(): Promise<boolean> {
    const c = this.host.env.coordinator;
    if (!this.host.isActive() || !this.host.env.webReady || this.host.state.loadState !== 'ready' || c === undefined) { return false; }
    const ok = await c.checkpointNow();
    if (!this.host.isActive() || c !== this.host.env.coordinator) { return false; }
    this.host.state.recoveryLabel = ok ? (c.state === SaveState.CLEAN ? '' : '恢复草稿已保留') : '恢复草稿写入失败，请立即保存或导出';
    if (!ok) { this.host.append('[草稿] 检查点失败，保留编辑器正文'); }
    return ok;
  }

  async onExternalOpen(): Promise<void> {
    if (this.host.state.deliveryBusy) { return; }
    if (!this.host.isActive() || this.host.env.openPromptVisible || this.host.env.pendingOpenUri.length === 0) { return; }
    const uri = this.host.env.pendingOpenUri;
    if (this.host.state.loadState !== 'ready' && this.host.state.docLength === 0) {
      this.host.env.pendingOpenUri = '';
      this.host.openReceivedDocument(uri);
      return;
    }
    this.host.env.openPromptVisible = true;
    if (!await this.host.protectDraft() || !this.host.isActive()) { this.host.env.openPromptVisible = false; return; }
    if (this.host.env.coordinator?.state === SaveState.CLEAN) {
      this.host.env.openPromptVisible = false;
      if (this.host.env.pendingOpenUri !== uri) { this.host.onExternalOpen(); return; }
      this.host.env.pendingOpenUri = '';
      this.host.openReceivedDocument(uri);
      return;
    }
    AlertDialog.show({
      title: '打开收到的文档',
      message: '先保留当前文档的恢复草稿，再打开收到的文件。',
      primaryButton: { value: '保留草稿并打开', action: () => {
        this.host.protectDraft().then((ok: boolean) => {
          this.host.env.openPromptVisible = false;
          if (!ok || this.host.env.pendingOpenUri !== uri) { this.host.onExternalOpen(); return; }
          this.host.env.pendingOpenUri = '';
          this.host.openReceivedDocument(uri);
        });
      } },
      secondaryButton: { value: '取消', action: () => { this.host.env.openPromptVisible = false; this.host.env.pendingOpenUri = ''; } },
      cancel: () => { this.host.env.openPromptVisible = false; this.host.env.pendingOpenUri = ''; },
    });
  }

  openReceivedDocument(id: string): void {
    router.replaceUrl({ url: 'pages/EditorPage', params: DocumentIntake.route(id) });
  }

  async receiveDrop(event: DragEvent): Promise<void> {
    this.host.state.fileHover = false;
    if (this.host.state.dropBusy || this.host.state.deliveryBusy) { promptAction.showToast({ message: '文件操作进行中，请稍后再拖入' }); return; }
    this.host.state.dropBusy = true;
    this.host.append('[拖入] 开始异步取数');
    try {
      const uri = await new DocumentImportService(this.host.env.ctx,
        (key: string) => this.host.uiContext.getDragController().cancelDataLoading(key)).receive(event);
      if (!this.host.isActive()) { return; }
      this.host.append('[拖入] 已取得单文档授权');
      promptAction.showToast({ message: '已导入“我的文档”，编辑的是副本' });
      this.host.env.pendingOpenUri = uri;
    } catch (e) {
      this.host.append('[拖入] 未完成，当前正文保留');
      if (this.host.isActive()) { promptAction.showToast({ message: String(e).replace(/^Error: /, '') }); }
    } finally { this.host.state.dropBusy = false; }
  }

  async switchToDocument(docId: string): Promise<void> {
    if (this.host.state.deliveryBusy || !await this.host.protectDraft()) { return; }
    const current = this.host.state.docTarget;
    if (current !== undefined && (current.kind === 'internal' ? current.relativePath : current.uri) === docId) { return; }
    const c = this.host.env.coordinator;
    if (c !== undefined && c.state !== SaveState.CLEAN) {
      const outcome = await c.saveNow(Date.now());
      this.host.state.saveState = c.state;
      if (!((outcome === 'saved' || outcome === 'unchanged') && SaveStateMachine.label(c.state) === '已保存' && !c.pending)) {
        promptAction.showToast({ message: '请先保存当前文档，或保留草稿返回首页再打开' }); return;
      }
    }
    const source: DocumentSource = docId.startsWith('library/')
      ? { kind: 'internal', relativePath: docId }
      : { kind: 'external', uri: docId, displayName: RecentFileList.displayName(docId) };
    this.host.state.docTarget = source;
    this.host.state.docTitle = RecentFileList.displayName(docId);
    this.host.env.docFormat = { encoding: 'utf-8', lineEnding: 'lf' };
    this.host.env.docValidUtf8 = true;
    this.host.loadOpenedDoc(source);
    this.host.refreshSidebarData();
  }

  resolveRouteParams(): void {
    const params = router.getParams();
    if (params === undefined || params === null) {
      return;
    }
    const pObj: ESObject = params as ESObject;
    const name = pObj.name as string | undefined;
    const uri = pObj.uri as string | undefined;
    if (name !== undefined && name.length > 0) {
      const src: InternalSource = { kind: 'internal', relativePath: name };
      this.host.state.docTarget = src;
      this.host.state.docTitle = name.substring(name.lastIndexOf('/') + 1);
      this.host.loadOpenedDoc(src);
    } else if (uri !== undefined && uri.length > 0) {
      const src: ExternalSource = { kind: 'external', uri: uri, displayName: uri };
      this.host.state.docTarget = src;
      this.host.state.docTitle = RecentFileList.displayName(uri);
      this.host.loadOpenedDoc(src);
    }
  }

  loadOpenedDoc(target: DocumentSource): void {
    const t0 = Date.now();
    this.host.state.loadState = 'loading';
    const src: DocumentFileAdapter = target.kind === 'internal' ? this.host.env.internal : this.host.env.external;
    const read = src.read(target);
    this.host.env.documentRead = read;
    read.then((r) => {
      if (!this.host.isActive() || read !== this.host.env.documentRead) { return; }
      this.host.env.expectedRevision = r.revision;
      this.host.env.pendingLoad = r.content;
      this.host.env.pendingLoadAt = t0;
      this.host.env.docFormat = { encoding: r.encoding, lineEnding: r.lineEnding };
      this.host.env.docValidUtf8 = r.validUtf8;
      this.host.state.loadState = 'ready';
      this.host.trackRecent(target).then(() => this.host.refreshSidebarData());
      if (this.host.env.webReady) {
        this.host.flushPendingLoad();
      }
    }).catch((e: ESObject) => {
      if (!this.host.isActive() || read !== this.host.env.documentRead) { return; }
      // A2-04：权限失效（重启后临时授权丢失/文件被移动删除）与普通读取失败分流通
      const msg = String(e);
      this.host.state.loadFailure = e.message === undefined ? msg : String(e.message);
      this.host.state.loadState = e.code === 13900001 || e.code === 13900002 || /13900001|13900002|permission|not permitted/i.test(msg)
        ? 'accessExpired' : 'loadFailed';
      this.host.append(`[打开] 失败（${this.host.state.loadState}）`);
    });
  }

  async reselectExternalFile(): Promise<void> {
    if (!this.host.isActive()) { return; }
    const session = this.host.env.activeSession;
    try {
      const documentPicker = new picker.DocumentViewPicker(this.host.env.ctx);
      const result: Array<string> = await documentPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.md', '.markdown', '.txt'],
      });
      if (!this.host.isActive() || session !== this.host.env.activeSession || result.length === 0) {
        return; // 用户取消：保持恢复面板
      }
      const src: ExternalSource = { kind: 'external', uri: result[0], displayName: result[0] };
      this.host.state.docTarget = src;
      this.host.state.docTitle = RecentFileList.displayName(result[0]);
      this.host.loadOpenedDoc(src);
    } catch (e) {
      this.host.append(`[重选] 选择器失败：${JSON.stringify(e)}`);
    }
  }

  async trackRecent(target: DocumentSource): Promise<void> {
    try {
      const id = target.kind === 'internal'
        ? (target as InternalSource).relativePath
        : (target as ExternalSource).uri;
      const entries = await this.host.env.meta.loadRecent();
      const list = new RecentFileList(entries);
      list.touch(id, Date.now());
      await this.host.env.meta.saveRecent(list.snapshot());
    } catch (e) {
      // 元数据失败不影响正文保存
    }
  }

  flushPendingLoad(): void {
    const md = this.host.env.pendingLoad;
    this.host.env.pendingLoad = '';
    const t0 = this.host.env.pendingLoadAt;
    this.host.env.activeSession = `s-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    const session = this.host.env.activeSession;
    const js = `window.__editorApi.loadDocument(${JSON.stringify(md)}, ${JSON.stringify(session)});`;
    this.host.runJsValue(js).then(() => {
      if (session !== this.host.env.activeSession || !this.host.isActive()) { return; }
      this.host.env.coordinator = new SaveCoordinator(new EditorPageDeps(
        () => this.host.getSnapshotData(), (content: string) => this.host.doSaveCheckpoint(content),
        (content: string) => this.host.doPersist(content), () => this.host.clearSavedDrafts()));
      this.host.state.saveState = SaveState.CLEAN;
      this.host.state.recoveryLabel = '';
      this.host.env.lastPreviewedMd = '\u0000';
      this.host.state.docLength = md.length;
      const dt = t0 > 0 ? Date.now() - t0 : -1;
      this.host.append(`[打开] 文档 ${md.length} 字符（打开至可编辑 ${dt}ms）`);
      const c0 = this.host.env.coordinator;
      if (c0 !== undefined) {
        c0.onDocumentLoaded(session);
      }
      this.host.syncDocNow();
    });
  }
}
