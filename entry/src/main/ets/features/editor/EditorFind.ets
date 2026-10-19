import { MuLogger } from '../../common/MuLogger';
import { FindReplaceEngine, FindOptions } from '../../domain/editor/FindReplaceEngine';
import { FindSession } from '../../domain/editor/FindSession';
import { DefaultView } from '../../domain/settings/AppSettings';
import { EditorController } from './EditorController';
export class EditorFind {
  private host: EditorController;
  constructor(host: EditorController) { this.host = host; }
  findOpts(): FindOptions {
    const opts: FindOptions = { caseSensitive: this.host.state.findCase, wholeWord: this.host.state.findWord };
    return opts;
  }

  openFind(): void {
    this.host.state.findVisible = true;
    // 预览态查找无选区可标：切回编辑视图
    if (this.host.state.viewMode === DefaultView.PREVIEW) {
      this.host.setViewMode(DefaultView.EDIT);
    }
    this.host.refreshFind().then(() => this.host.locateFirstMatch());
  }

  async refreshFind(): Promise<void> {
    if (this.host.state.findQuery.length === 0) {
      this.host.state.findMatches = [];
      this.host.state.matchIndex = -1;
      return;
    }
    const session = this.host.env.activeSession;
    const query = this.host.state.findQuery;
    const options = this.host.findOpts();
    const coordinator = this.host.env.coordinator;
    const snapshot = await this.host.getSnapshotData();
    if (!this.host.isActive() || session !== this.host.env.activeSession || query !== this.host.state.findQuery ||
      options.caseSensitive !== this.host.state.findCase || options.wholeWord !== this.host.state.findWord ||
      coordinator !== this.host.env.coordinator || !snapshot.ok || snapshot.sessionId !== session ||
      snapshot.version < (coordinator?.documentVersion ?? 0)) { return; }
    this.host.updateFindMatches(snapshot.content);
  }

  updateFindMatches(text: string): void {
    this.host.state.findMatches = FindReplaceEngine.findAll(text, this.host.state.findQuery, this.host.findOpts());
    this.host.state.matchIndex = Math.min(Math.max(0, this.host.state.matchIndex), this.host.state.matchCount - 1);
  }

  jumpNext(): void {
    this.host.state.matchIndex = FindSession.next(this.host.state.matchCount, this.host.state.matchIndex);
    this.host.selectCurrentMatch();
  }

  locateFirstMatch(): void {
    if (this.host.isActive() && this.host.state.findVisible && this.host.state.matchCount > 0) {
      if (this.host.state.matchIndex < 0) { this.host.state.matchIndex = 0; }
      this.host.selectCurrentMatch();
    }
  }

  jumpPrev(): void {
    this.host.state.matchIndex = FindSession.prev(this.host.state.matchCount, this.host.state.matchIndex);
    this.host.selectCurrentMatch();
  }

  selectCurrentMatch(): void {
    if (this.host.state.matchIndex < 0 || this.host.state.matchIndex >= this.host.state.findMatches.length) {
      return;
    }
    const m = this.host.state.findMatches[this.host.state.matchIndex];
    this.host.runJsValue(`window.__editorApi.setSelectionRange(${m.from}, ${m.to});`);
  }

  async replaceCurrent(): Promise<void> {
    if (this.host.state.deliveryBusy) { return; }
    if (this.host.state.findQuery.length === 0) {
      return;
    }
    const text = await this.host.runJsValue('window.__editorApi.getSnapshot();');
    const from = this.host.state.matchIndex >= 0 && this.host.state.matchIndex < this.host.state.findMatches.length
      ? this.host.state.findMatches[this.host.state.matchIndex].from
      : 0;
    const r = FindReplaceEngine.replaceCurrent(text, this.host.state.findQuery, this.host.state.replaceText, from, this.host.findOpts());
    if (!r.replaced) {
      return;
    }
    await this.host.runJsValue(`window.__editorApi.setDocument(${JSON.stringify(r.text)}, ${r.newCursor}, ${r.newCursor});`);
    this.host.state.docLength = r.text.length;
    this.host.markEdited();
    // 替换改变了正文：同步重算命中（替换处已消失，从锚点前进到下一处）
    const anchor = this.host.state.matchIndex;
    this.host.state.findMatches = FindReplaceEngine.findAll(r.text, this.host.state.findQuery, this.host.findOpts());
    this.host.state.matchIndex = FindSession.next(this.host.state.matchCount, Math.min(anchor, this.host.state.matchCount - 1));
    this.host.selectCurrentMatch();
  }

  async replaceAllMatches(): Promise<void> {
    if (this.host.state.deliveryBusy) { return; }
    if (this.host.state.findQuery.length === 0) {
      return;
    }
    const text = await this.host.runJsValue('window.__editorApi.getSnapshot();');
    const r = FindReplaceEngine.replaceAll(text, this.host.state.findQuery, this.host.state.replaceText, this.host.findOpts());
    if (r.count === 0) {
      return;
    }
    const pos = r.undos.length > 0 ? r.undos[0].from : 0;
    await this.host.runJsValue(`window.__editorApi.setDocument(${JSON.stringify(r.text)}, ${pos}, ${pos});`);
    this.host.state.docLength = r.text.length;
    this.host.markEdited();
    // 全部替换后命中归零
    this.host.state.findMatches = [];
    this.host.state.matchIndex = -1;
    MuLogger.info(`[替换] 全部替换 ${r.count} 处`);
  }

  markEdited(): void {
    const c = this.host.env.coordinator;
    if (c !== undefined) {
      c.onEdit(Date.now());
      this.host.state.saveState = c.state;
    }
    this.host.scheduleDocSync();
  }
}
