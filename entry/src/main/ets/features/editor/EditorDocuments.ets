import { MuLogger } from '../../common/MuLogger';
import { router, promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { SaveState, SaveStateMachine } from '../../domain/recovery/SaveStateMachine';
import { DocumentImportService } from '../../services/DocumentImportService';
import { DocumentIntake } from '../../domain/document/DocumentIntake';
import { DocumentFileAdapter, DocumentSource, InternalSource, ExternalSource } from '../../domain/document/DocumentFileAdapter';
import { RecentFileList } from '../../domain/document/RecentFileList';
import { FileNameValidator } from '../../domain/document/FileNameValidator';
import { EditorController } from './EditorController';
export class EditorDocuments {
  private host: EditorController;
  constructor(host: EditorController) { this.host = host; }
  async toggleRecentPin(docId: string): Promise<void> {
    try {
      const entries = await this.host.env.meta.loadRecent();
      const list = new RecentFileList(entries);
      list.setPinned(docId, !entries.find((e) => e.documentId === docId)?.pinned);
      await this.host.env.meta.saveRecent(list.snapshot());
      if (this.host.isActive()) { this.host.refreshSidebarData(); }
    } catch (e) {
      MuLogger.warn('[最近] 置顶失败');
      promptAction.showToast({ message: '置顶失败，请重试' });
    }
  }

  deleteDocument(docId: string): void {
    if (!this.host.isActive() || this.host.state.deliveryBusy) { return; }
    if (!docId.startsWith('library/')) {
      promptAction.showToast({ message: '外部原文件请在文件管理器中删除' });
      return;
    }
    if (FileNameValidator.validate(docId.substring('library/'.length)) !== undefined) {
      promptAction.showToast({ message: '无效的应用内文件名，无法删除' });
      return;
    }
    const target = this.host.state.docTarget;
    if (target?.kind === 'internal' && target.relativePath === docId) {
      promptAction.showToast({ message: '请先切换到其他文档，再删除当前文档' });
      return;
    }
    AlertDialog.show({
      title: '删除文档', message: `确定删除“${RecentFileList.displayName(docId)}”？文件将直接删除，无法恢复。`,
      primaryButton: { value: '删除', fontColor: this.host.state.pal.DANGER,
        action: () => { this.deleteConfirmed(docId); } },
      secondaryButton: { value: '取消', action: () => {} },
    });
  }

  private async deleteConfirmed(docId: string): Promise<void> {
    const target = this.host.state.docTarget;
    if (!this.host.isActive() || this.host.state.deliveryBusy ||
      (target?.kind === 'internal' && target.relativePath === docId)) { return; }
    this.host.state.deliveryBusy = true;
    try {
      if (!this.host.env.internal.deleteLibrary(docId.substring('library/'.length))) {
        promptAction.showToast({ message: '删除失败，请重试' });
        return;
      }
      this.host.env.drafts.remove(`internal:${docId}`);
      const entries = await this.host.env.meta.loadRecent();
      const list = new RecentFileList(entries);
      list.remove(docId);
      await this.host.env.meta.saveRecent(list.snapshot());
      promptAction.showToast({ message: '已删除' });
    } catch (e) {
      MuLogger.warn('[最近] 文件已删除，但最近记录更新失败');
      promptAction.showToast({ message: '文件已删除，但最近记录更新失败' });
    } finally {
      this.host.state.deliveryBusy = false;
      if (this.host.isActive()) { this.host.refreshSidebarData(); }
    }
  }

  async protectDraft(): Promise<boolean> {
    const c = this.host.env.coordinator;
    if (!this.host.isActive() || !this.host.env.webReady || this.host.state.loadState !== 'ready' || c === undefined) { return false; }
    const ok = await c.checkpointNow();
    if (!this.host.isActive() || c !== this.host.env.coordinator) { return false; }
    this.host.state.recoveryLabel = ok ? (c.state === SaveState.CLEAN ? '' : '恢复草稿已保留') : '恢复草稿写入失败，请立即保存或导出';
    if (!ok) { MuLogger.info('[草稿] 检查点失败，保留编辑器正文'); }
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
    if (DocumentIntake.isHtml(uri)) {
      this.host.env.openPromptVisible = false;
      if (this.host.env.pendingOpenUri !== uri) { this.host.onExternalOpen(); return; }
      this.host.env.pendingOpenUri = '';
      this.openReceivedDocument(uri);
      return;
    }
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
    if (DocumentIntake.isHtml(id)) {
      router.pushUrl({ url: DocumentIntake.page(id), params: DocumentIntake.route(id) });
      return;
    }
    router.replaceUrl({ url: 'pages/EditorPage', params: DocumentIntake.route(id) });
  }

  async receiveDrop(event: DragEvent): Promise<void> {
    this.host.state.fileHover = false;
    if (this.host.state.dropBusy || this.host.state.deliveryBusy) { promptAction.showToast({ message: '文件操作进行中，请稍后再拖入' }); return; }
    this.host.state.dropBusy = true;
    MuLogger.info('[拖入] 开始异步取数');
    try {
      const uri = await new DocumentImportService(this.host.env.ctx,
        (key: string) => this.host.uiContext.getDragController().cancelDataLoading(key)).receive(event);
      if (!this.host.isActive()) { return; }
      MuLogger.info('[拖入] 已取得单文档授权');
      if (DocumentIntake.isHtml(uri)) { await this.host.insertHtml(uri); return; }
      promptAction.showToast({ message: '已导入“我的文档”，编辑的是副本' });
      this.host.env.pendingOpenUri = uri;
    } catch (e) {
      MuLogger.info('[拖入] 未完成，当前正文保留');
      if (this.host.isActive()) { promptAction.showToast({ message: String(e).replace(/^Error: /, '') }); }
    } finally { this.host.state.dropBusy = false; }
  }

  async switchToDocument(docId: string): Promise<void> {
    if (this.host.state.deliveryBusy || !await this.host.protectDraft()) { return; }
    if (DocumentIntake.isHtml(docId)) { this.openReceivedDocument(docId); return; }
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
      this.host.trackRecent(target);
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
      MuLogger.info(`[打开] 失败（${this.host.state.loadState}）`);
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
      MuLogger.info(`[重选] 选择器失败：${JSON.stringify(e)}`);
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
      if (this.host.isActive()) { this.host.refreshSidebarData(); }
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
    // loadDocument 正常返回 undefined；载入失败必须呈现错误态，不能把空白编辑器当已打开文档。
    this.host.runJsChecked(this.host.env.controller, js, true).then(() => {
      if (session !== this.host.env.activeSession || !this.host.isActive()) { return; }
      this.host.env.coordinator = this.host.createSaveCoordinator();
      this.host.state.saveState = SaveState.CLEAN;
      this.host.state.recoveryLabel = '';
      this.host.env.lastPreviewedMd = '\u0000';
      this.host.state.docLength = md.length;
      const dt = t0 > 0 ? Date.now() - t0 : -1;
      MuLogger.info(`[打开] 文档 ${md.length} 字符（打开至可编辑 ${dt}ms）`);
      const c0 = this.host.env.coordinator;
      if (c0 !== undefined) {
        c0.onDocumentLoaded(session);
      }
      this.host.syncDocNow();
    }).catch((e: ESObject) => {
      if (session !== this.host.env.activeSession || !this.host.isActive()) { return; }
      this.host.state.loadFailure = '编辑器未能载入文件内容，请返回后重新打开';
      this.host.state.loadState = 'loadFailed';
      MuLogger.warn(`[打开] 编辑器载入失败：${JSON.stringify(e)}`);
    });
  }
}
