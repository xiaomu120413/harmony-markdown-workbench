import { router, promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { SaveState, SaveStateMachine } from '../../domain/recovery/SaveStateMachine';
import { SnapshotData } from '../../services/SaveCoordinator';
import { DocumentFileAdapter, DocumentSource, InternalSource, ExternalSource, WriteDocumentResult, WriteFailResult } from '../../domain/document/DocumentFileAdapter';
import { DocumentNamer } from '../../domain/document/DocumentNamer';
import { EditorController } from './EditorController';
export class EditorPersistence {
  private host: EditorController;
  constructor(host: EditorController) { this.host = host; }
  doSaveCheckpoint(content: string): Promise<void> {
    const target = this.host.state.docTarget;
    if (target === undefined) {
      this.host.env.drafts.save(
        this.host.state.sessionDraftId,
        'session:new',
        0,
        '',
        content,
      );
      return Promise.resolve();
    }
    this.host.env.drafts.save(
      this.host.draftIdOf(target),
      this.host.fingerprintOf(target),
      this.host.state.expectedRevision.size,
      this.host.state.expectedRevision.contentHash,
      content,
    );
    // 首次持久化成功后会清正式草稿；会话草稿一并在 doPersist 迁移清理
    return Promise.resolve();
  }

  async doPersist(content: string): Promise<WriteDocumentResult> {
    let target = this.host.state.docTarget;
    if (target === undefined) {
      const name = DocumentNamer.derive(content, this.host.env.internal.listLibrary());
      const src: InternalSource = { kind: 'internal', relativePath: `library/${name}` };
      target = src;
      this.host.state.docTarget = src;
      this.host.state.docTitle = name;
      this.host.append(`[保存] 新建文档 → 资料库/${name}`);
    } else if (target.kind === 'internal') {
      // 自动名升级：首次自动保存常发生在标题输入完成前，标题可用时重命名
      const currentName = (target as InternalSource).relativePath.substring('library/'.length);
      const better = DocumentNamer.upgrade(currentName, content, this.host.env.internal.listLibrary());
      if (better !== undefined) {
        const renamed: InternalSource = { kind: 'internal', relativePath: `library/${better}` };
        const w = await this.host.env.internal.write(renamed, content, { size: 0, contentHash: '' }, this.host.state.docFormat);
        if (w.ok) {
          this.host.state.retiredDraftId = this.host.draftIdOf(target);
          this.host.env.internal.remove(target);
          this.host.state.docTarget = renamed;
          this.host.state.docTitle = better;
          this.host.state.expectedRevision = w.revision;
          // 原名草稿保留供恢复页按内容核对。


          this.host.trackRecent(renamed);
          this.host.append(`[保存] 自动名升级 → 资料库/${better}`);
          return w;
        }
        // 升级写入失败：按原名继续保存
      }
    }
    if (target.kind === 'external' && this.host.state.loadState !== 'ready') {
      // A2：外部文档未成功加载（accessExpired/loadFailed）时禁止原位写回
      const fail: WriteFailResult = { ok: false, reason: 'io', message: 'document not loaded; write-back blocked' };
      return fail;
    }
    if (!this.host.state.docValidUtf8) {
      // A4-04：非 UTF-8 文档不静默乱码覆盖——阻断原位写回（内容仍可另存副本）
      const fail: WriteFailResult = { ok: false, reason: 'io', message: 'non-UTF-8 document; write-back blocked' };
      return fail;
    }
    const result = target.kind === 'internal'
      ? await this.host.env.internal.write(target, content, this.host.state.expectedRevision, this.host.state.docFormat)
      : await this.host.env.external.write(target, content, this.host.state.expectedRevision, this.host.state.docFormat);
    if (result.ok) {
      this.host.state.expectedRevision = result.revision;
      // 恢复页按实际磁盘内容清理冗余，不能在旧版本提交时删除新草稿。
      // A3：正式目标确立后清理会话草稿（迁移完成）

      this.host.trackRecent(target);
    }
    return result;
  }

  clearSavedDrafts(): Promise<void> {
    if (this.host.state.retiredDraftId.length > 0) { this.host.env.drafts.remove(this.host.state.retiredDraftId); this.host.state.retiredDraftId = ''; }
    this.host.state.recoveryLabel = '';
    if (this.host.state.docTarget !== undefined) { this.host.env.drafts.remove(this.host.draftIdOf(this.host.state.docTarget)); }
    this.host.env.drafts.remove(this.host.state.sessionDraftId);
    return Promise.resolve();
  }

  draftIdOf(target: DocumentSource): string {
    if (target.kind === 'internal') {
      return `internal:${(target as InternalSource).relativePath}`;
    }
    return `external:${(target as ExternalSource).uri}`;
  }

  fingerprintOf(target: DocumentSource): string {
    if (target.kind === 'internal') {
      return `internal:${(target as InternalSource).relativePath}`;
    }
    return `external:${(target as ExternalSource).uri}`;
  }

  async requestLeave(): Promise<void> {
    const c = this.host.env.coordinator;
    if (c === undefined) {
      router.back();
      return;
    }
    if (c.state === SaveState.CLEAN) {
      router.back();
      return;
    }
    const outcome = await c.saveNow(Date.now());
    this.host.state.saveLabel = SaveStateMachine.label(c.state);
    this.host.state.conflictVisible = c.state === SaveState.CONFLICT;
    // saved + 无待保存（保存期间无新编辑，A1 版本门控）→ 干净离开
    if ((outcome === 'saved' || outcome === 'unchanged') && SaveStateMachine.label(c.state) === '已保存' && !c.pending) {
      router.back();
      return;
    }
    // 失败/冲突/保存期间新编辑：留在页面，给出可执行下一步
    AlertDialog.show({
      title: '暂时无法离开',
      message: outcome === 'conflict' || c.state === SaveState.CONFLICT
        ? '磁盘版本已变化，请先在冲突条中选择处理方式。'
        : '保存未完成，请重试或导出副本；退出前请确认恢复草稿状态。',
      primaryButton: {
        value: '重试保存',
        action: () => {
          this.host.requestLeave();
        },
      },
      secondaryButton: {
        value: '放弃修改离开',
        action: () => {
          router.back();
        },
      },
      cancel: () => {
        // 留在页面继续编辑
      },
    });
  }

  async goBack(): Promise<void> {
    if (this.host.state.deliveryBusy) { promptAction.showToast({ message: '请先完成或取消文件操作' }); return; }
    if (this.host.state.loadState === 'ready' && this.host.state.webReady && !await this.host.protectDraft()) {
      promptAction.showToast({ message: '恢复草稿未确认写入，请保存或导出后离开' }); return;
    }
    const c = this.host.env.coordinator;
    if (c !== undefined && c.state !== SaveState.CLEAN) {
      AlertDialog.show({
        title: '未保存修改',
        message: '仍有未保存内容。保存成功后离开，或保留恢复草稿后离开。',
        primaryButton: {
          value: '保存并离开',
          action: () => {
            this.host.requestLeave();
          },
        },
        secondaryButton: {
          value: '保留草稿离开',
          action: () => { this.host.protectDraft().then((ok: boolean) => { if (ok) { router.back(); } }); },
        },
        cancel: () => {
          // 取消：留在页面继续编辑
        },
      });
      return;
    }
    router.back();
  }

  async getSnapshotData(): Promise<SnapshotData> {
    try {
      const raw = await this.host.runJsChecked(this.host.env.controller, 'window.__editorApi.getSnapshotEx();');
      const o: ESObject = JSON.parse(raw);
      const d: SnapshotData = {
        ok: o.ok === true && typeof o.c === 'string' && typeof o.v === 'number' && o.s === this.host.state.activeSession,
        sessionId: `${o.s}`,
        version: o.v as number,
        content: `${o.c}`,
      };
      return d;
    } catch (e) {
      const fail: SnapshotData = { ok: false, sessionId: '', version: 0, content: '' };
      return fail;
    }
  }

  async save(): Promise<void> {
    if (this.host.state.deliveryBusy) { return; }
    const c = this.host.env.coordinator;
    if (c === undefined) {
      return;
    }
    if (!await this.host.protectDraft()) {
      promptAction.showToast({ message: '无法确认正文快照，请重试或导出' }); return;
    }
    if (c.state === SaveState.CLEAN) {
      this.host.append('[保存] 无修改');
      return;
    }
    const outcome = await c.saveNow(Date.now());
    this.host.state.saveLabel = SaveStateMachine.label(c.state);
    this.host.state.conflictVisible = c.state === SaveState.CONFLICT;
    if (outcome === 'saved' || outcome === 'unchanged') {
      this.host.append(`[保存] ${outcome === 'saved' ? '完成' : '无修改'} → ${this.host.state.saveLabel}`);
    } else if (outcome === 'failed') {
      this.host.append('[保存] 失败，正文与草稿检查点已保留');
    } else if (outcome === 'busy') {
      this.host.append('[保存] 已有保存在进行中，稍后自动收敛');
    }
  }

  conflictKeepDisk(): void {
    if (this.host.state.deliveryBusy) { return; }
    const c = this.host.env.coordinator;
    const target = this.host.state.docTarget;
    if (c === undefined || target === undefined) {
      return;
    }
    const src: DocumentFileAdapter = target.kind === 'internal' ? this.host.env.internal : this.host.env.external;
    src.read(target).then((r) => {
      this.host.state.expectedRevision = r.revision;
      this.host.state.pendingLoad = r.content;
      this.host.flushPendingLoad();
      c.decideKeepDisk();
      this.host.state.conflictVisible = false;
      this.host.state.saveLabel = SaveStateMachine.label(c.state);
      this.host.append('[冲突] 已加载磁盘版本');
    }).catch((e: ESObject) => {
      this.host.append(`[冲突] 读取磁盘版本失败：${JSON.stringify(e)}（保留本地编辑）`);
      c.decideKeepLocal();
      this.host.state.conflictVisible = false;
      this.host.state.saveLabel = SaveStateMachine.label(c.state);
    });
  }

  conflictKeepLocal(): void {
    if (this.host.state.deliveryBusy) { return; }
    const c = this.host.env.coordinator;
    if (c === undefined) {
      return;
    }
    c.decideKeepLocal();
    this.host.state.conflictVisible = false;
    this.host.state.saveLabel = SaveStateMachine.label(c.state);
    this.host.append('[冲突] 保留本地内容继续编辑');
  }

  conflictSaveCopy(): void {
    this.host.deliverDocument(0);
  }

  async openDocument(): Promise<void> {
    if (!this.host.isActive() || this.host.state.deliveryBusy || this.host.state.dropBusy) { return; }
    const session = this.host.state.activeSession;
    try {
      const uris = await new picker.DocumentViewPicker(this.host.env.ctx).select({
        maxSelectNumber: 1, fileSuffixFilters: ['.md', '.markdown', '.txt'],
      });
      if (this.host.isActive() && session === this.host.state.activeSession && uris.length > 0) { this.host.state.pendingOpenUri = uris[0]; }
    } catch (e) { this.host.append('[打开] 选择器未完成'); promptAction.showToast({ message: '打开失败，请重试' }); }
  }

  async newDocument(): Promise<void> {
    if (this.host.state.deliveryBusy || !await this.host.protectDraft()) { return; }
    if (this.host.env.coordinator?.state === SaveState.CLEAN) {
      router.replaceUrl({ url: 'pages/EditorPage' }); return;
    }
    AlertDialog.show({ title: '新建文档', message: '当前修改已保留为恢复草稿。新建后可从首页“找回未保存内容”继续。',
      primaryButton: { value: '保留草稿并新建', action: () => {
        this.host.protectDraft().then((ok: boolean) => { if (ok) { router.replaceUrl({ url: 'pages/EditorPage' }); } });
      } }, secondaryButton: { value: '取消', action: () => {} } });
  }
}
