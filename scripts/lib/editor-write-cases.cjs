'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');

/** 编辑器写回安全、文档载入与资料库重命名用例（由 test-host.cjs 汇总执行）。 */
module.exports = function registerEditorWriteCases({ load, root, cases, toasts }) {
  // ---- 编辑器写回安全：读取失败必须中止，写失败不得推进保存/命中状态 ----
  const { EditorController } = load(path.join(root, 'entry/src/main/ets/features/editor/EditorController.ets'));
  const { EditorFind } = load(path.join(root, 'entry/src/main/ets/features/editor/EditorFind.ets'));
  const { EditorDelivery } = load(path.join(root, 'entry/src/main/ets/features/editor/EditorDelivery.ets'));
  function findHost(handler) {
    const state = {
      deliveryBusy: false, findQuery: 'foo', replaceText: 'bar', findCase: false, findWord: false,
      matchIndex: 0, findMatches: [{ from: 0, to: 3 }], docLength: 99, saveState: 'clean',
      get matchCount() { return this.findMatches.length; },
    };
    const env = { activeSession: 's1', controller: {}, coordinator: undefined };
    let edits = 0;
    return {
      state, env, isActive: () => true,
      findOpts: () => ({ caseSensitive: false, wholeWord: false }),
      runJsChecked: async (ctrl, script, allowEmpty) => {
        const value = handler(script);
        if (value === undefined && !allowEmpty) throw new Error('editor read failed');
        return value === undefined ? '' : value;
      },
      markEdited: () => { edits++; },
      selectCurrentMatch: () => {},
      editCount: () => edits,
    };
  }
  cases.push({ name: 'find replace aborts before writing when snapshot read fails', async body() {
    const host = findHost(script => { if (script.includes('getSnapshot')) throw new Error('read failed'); return ''; });
    await new EditorFind(host).replaceCurrent();
    assert.equal(host.state.docLength, 99); assert.equal(host.editCount(), 0);
  } });
  cases.push({ name: 'find replace failure keeps doc length and save state untouched', async body() {
    const host = findHost(script => {
      if (script.includes('getSnapshot')) return 'foo baz';
      throw new Error('write failed');
    });
    await new EditorFind(host).replaceCurrent();
    assert.equal(host.state.docLength, 99); assert.equal(host.editCount(), 0);
  } });
  cases.push({ name: 'find replace advances state only after write succeeds', async body() {
    const scripts = [];
    const host = findHost(script => { scripts.push(script); return script.includes('getSnapshot') ? 'foo baz' : undefined; });
    await new EditorFind(host).replaceCurrent();
    assert.ok(scripts.some(s => s.includes('setDocument')));
    assert.equal(host.state.docLength, 7); assert.equal(host.editCount(), 1);
  } });
  cases.push({ name: 'replace-all failure preserves matches and does not mark edited', async body() {
    const host = findHost(script => {
      if (script.includes('getSnapshot')) return 'foo foo';
      throw new Error('write failed');
    });
    host.state.findMatches = [{ from: 0, to: 3 }, { from: 4, to: 7 }];
    host.state.matchIndex = 1;
    await new EditorFind(host).replaceAllMatches();
    assert.equal(host.state.docLength, 99); assert.equal(host.state.findMatches.length, 2);
    assert.equal(host.state.matchIndex, 1); assert.equal(host.editCount(), 0);
  } });
  cases.push({ name: 'replace-all clears matches only after the write succeeds', async body() {
    const host = findHost(script => script.includes('getSnapshot') ? 'foo foo' : undefined);
    await new EditorFind(host).replaceAllMatches();
    assert.equal(host.state.docLength, 7); assert.equal(host.state.findMatches.length, 0);
    assert.equal(host.state.matchIndex, -1); assert.equal(host.editCount(), 1);
  } });
  function controllerHost(handler) {
    const host = Object.create(EditorController.prototype);
    host.state = { deliveryBusy: false, docLength: 99 };
    host.env = { activeSession: 's1', controller: { runJavaScript(script, cb) {
      try { cb(null, handler(script)); } catch (e) { cb(e, undefined); }
    } } };
    host.isActive = () => true;
    let edits = 0;
    host.markEdited = () => { edits++; };
    host.editCount = () => edits;
    return host;
  }
  cases.push({ name: 'toolbar command aborts when selection read fails', async body() {
    const host = controllerHost(script => { if (script.includes('getSelectionRange')) throw new Error('read failed'); return '{}'; });
    await host.applyCommand('bold');
    assert.equal(host.state.docLength, 99); assert.equal(host.editCount(), 0);
  } });
  cases.push({ name: 'toolbar command aborts when snapshot read fails', async body() {
    const scripts = [];
    const host = controllerHost(script => {
      scripts.push(script);
      if (script.includes('getSelectionRange')) return '{"from":0,"to":3}';
      throw new Error('read failed');
    });
    await host.applyCommand('bold');
    assert.ok(!scripts.some(s => s.includes('setDocument')));
    assert.equal(host.state.docLength, 99); assert.equal(host.editCount(), 0);
  } });
  cases.push({ name: 'toolbar command write failure does not mark document edited', async body() {
    const host = controllerHost(script => {
      if (script.includes('getSelectionRange')) return '{"from":0,"to":3}';
      if (script.includes('getSnapshot')) return 'foo';
      throw new Error('write failed');
    });
    await host.applyCommand('bold');
    assert.equal(host.state.docLength, 99); assert.equal(host.editCount(), 0);
  } });
  cases.push({ name: 'toolbar command aborts after session switch without writing', async body() {
    const scripts = [];
    const host = controllerHost(script => {
      scripts.push(script);
      if (script.includes('getSelectionRange')) return '{"from":0,"to":3}';
      host.env.activeSession = 's2';
      return 'foo';
    });
    await host.applyCommand('bold');
    assert.ok(!scripts.some(s => s.includes('setDocument')));
    assert.equal(host.state.docLength, 99); assert.equal(host.editCount(), 0);
  } });
  cases.push({ name: 'toolbar command writes once and advances state on success', async body() {
    const scripts = [];
    const host = controllerHost(script => {
      scripts.push(script);
      if (script.includes('getSelectionRange')) return '{"from":0,"to":3}';
      if (script.includes('getSnapshot')) return 'foo';
      return '7';
    });
    await host.applyCommand('bold');
    assert.equal(scripts.filter(s => s.includes('setDocument')).length, 1);
    assert.ok(scripts.find(s => s.includes('setDocument')).includes('**foo**'));
    assert.equal(host.state.docLength, 7); assert.equal(host.editCount(), 1);
  } });
  function deliveryHost(handler) {
    const calls = { edits: 0, syncs: 0 };
    const host = {
      state: { saveState: 'clean', deliveryBusy: false },
      env: {
        activeSession: 's1', controller: {},
        coordinator: { state: 'dirty', onEdit: () => { calls.edits++; } },
        internal: { copyToAttachments: () => 'attachments/picked.png' },
      },
      isActive: () => true,
      scheduleDocSync: () => { calls.syncs++; },
      runJsChecked: async (ctrl, script, allowEmpty) => {
        const value = handler(script, host);
        if (value === undefined && !allowEmpty) throw new Error('editor read failed');
        return value === undefined ? '' : value;
      },
      calls,
    };
    return host;
  }
  cases.push({ name: 'attachment insert aborts when selection read fails', async body() {
    const host = deliveryHost(() => { throw new Error('read failed'); });
    await assert.rejects(new EditorDelivery(host).insertAttachment('attachments/a.png', '图片', 's1'));
    assert.equal(host.calls.edits, 0); assert.equal(host.calls.syncs, 0); assert.equal(host.state.saveState, 'clean');
  } });
  cases.push({ name: 'attachment insert write failure leaves save state untouched', async body() {
    const host = deliveryHost(script => {
      if (script.includes('getSelectionRange')) return '{"from":2,"to":2}';
      throw new Error('write failed');
    });
    await assert.rejects(new EditorDelivery(host).insertAttachment('attachments/a.png', '图片', 's1'));
    assert.equal(host.calls.edits, 0); assert.equal(host.calls.syncs, 0); assert.equal(host.state.saveState, 'clean');
  } });
  cases.push({ name: 'attachment insert succeeds only after the write resolves', async body() {
    const host = deliveryHost(script => script.includes('getSelectionRange') ? '{"from":2,"to":2}' : undefined);
    assert.equal(await new EditorDelivery(host).insertAttachment('attachments/a.png', '图片', 's1'), true);
    assert.equal(host.calls.edits, 1); assert.equal(host.calls.syncs, 1); assert.equal(host.state.saveState, 'dirty');
  } });
  cases.push({ name: 'attachment insert stops silently when document switches during write', async body() {
    const host = deliveryHost(script => {
      if (script.includes('getSelectionRange')) return '{"from":2,"to":2}';
      host.env.activeSession = 's2';
      return undefined;
    });
    assert.equal(await new EditorDelivery(host).insertAttachment('attachments/a.png', '图片', 's1'), false);
    assert.equal(host.calls.edits, 0); assert.equal(host.calls.syncs, 0); assert.equal(host.state.saveState, 'clean');
  } });
  cases.push({ name: 'image picker reports failure instead of success when insert write fails', async body() {
    toasts.length = 0;
    const host = deliveryHost(script => {
      if (script.includes('getSelectionRange')) return '{"from":0,"to":0}';
      throw new Error('write failed');
    });
    await new EditorDelivery(host).insertLocalImage();
    assert.deepEqual(toasts, ['图片插入失败，请重试']);
    assert.equal(host.calls.edits, 0);
  } });
  cases.push({ name: 'image picker reports success only after the insert write resolves', async body() {
    toasts.length = 0;
    const host = deliveryHost(script => script.includes('getSelectionRange') ? '{"from":0,"to":0}' : undefined);
    await new EditorDelivery(host).insertLocalImage();
    assert.deepEqual(toasts, ['已插入 picked.png']);
    assert.equal(host.calls.edits, 1);
  } });
  // ---- 资料库重命名：复用 FileNameValidator，非法名不得进入文件操作 ----
  const { HomeController } = load(path.join(root, 'entry/src/main/ets/features/home/HomeController.ets'));
  const { EditorDocuments } = load(path.join(root, 'entry/src/main/ets/features/editor/EditorDocuments.ets'));
  function documentsHost(runJsChecked) {
    let coordinators = 0;
    return {
      state: { loadState: 'ready', docLength: 0, saveState: 'clean', recoveryLabel: 'old', loadFailure: '' },
      env: { pendingLoad: 'hello', pendingLoadAt: 1, activeSession: 'old', controller: {}, lastPreviewedMd: 'x', coordinator: undefined },
      isActive: () => true,
      runJsChecked,
      createSaveCoordinator: () => { coordinators++; return { onDocumentLoaded() {} }; },
      syncDocNow: () => {},
      coordinatorCount: () => coordinators,
    };
  }
  cases.push({ name: 'document load failure surfaces error instead of a blank ready editor', async body() {
    const host = documentsHost(async () => { throw new Error('editor down'); });
    new EditorDocuments(host).flushPendingLoad();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(host.state.loadState, 'loadFailed');
    assert.equal(host.coordinatorCount(), 0);
    assert.equal(host.state.docLength, 0);
    assert.equal(host.env.lastPreviewedMd, 'x');
  } });
  cases.push({ name: 'document load allows undefined write result and starts autosave after success', async body() {
    const calls = [];
    const host = documentsHost(async (ctrl, script, allowEmpty) => { calls.push([script, allowEmpty]); return ''; });
    new EditorDocuments(host).flushPendingLoad();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(calls.length, 1);
    assert.equal(calls[0][1], true);
    assert.match(calls[0][0], /loadDocument/);
    assert.equal(host.coordinatorCount(), 1);
    assert.equal(host.state.docLength, 5);
    assert.equal(host.state.loadState, 'ready');
  } });
  function homeHost(renamingFrom, renameText, library) {
    const host = Object.create(HomeController.prototype);
    host.state = { renamingFrom, renameText, searchQuery: '' };
    const renamed = [];
    host.env = {
      fileSource: {
        listLibrary: () => library.slice(),
        renameLibrary: (from, to) => { renamed.push(`${from}>${to}`); return true; },
      },
      meta: { loadRecent: async () => [], saveRecent: async () => {} },
    };
    host.uiContext = {};
    host.refresh = () => {};
    host.refreshLibrary = () => {};
    host.runSearch = () => {};
    return { host, renamed };
  }
  cases.push({ name: 'library rename rejects hidden, control and separator names', async body() {
    for (const item of [['.hidden', '文件名不能以点开头'], ['bad\u0000name', '文件名不能包含控制字符'],
      ['../evil', '文件名不能包含路径分隔符']]) {
      toasts.length = 0;
      const { host, renamed } = homeHost('old.md', item[0], ['old.md']);
      await host.confirmRename();
      assert.equal(renamed.length, 0, item[0]);
      assert.deepEqual(toasts, [item[1]], item[0]);
    }
  } });
  cases.push({ name: 'library rename keeps duplicate-name rejection', async body() {
    toasts.length = 0;
    const { host, renamed } = homeHost('old.md', 'taken', ['old.md', 'taken.md']);
    await host.confirmRename();
    assert.equal(renamed.length, 0);
    assert.deepEqual(toasts, ['名称已存在']);
  } });
  cases.push({ name: 'library rename appends markdown extension and renames once', async body() {
    toasts.length = 0;
    const { host, renamed } = homeHost('old.md', 'new name', ['old.md']);
    await host.confirmRename();
    assert.deepEqual(renamed, ['old.md>new name.md']);
    assert.deepEqual(toasts, ['已重命名为 new name.md']);
  } });
  cases.push({ name: 'library rename keeps HTML extension for an HTML document', async body() {
    toasts.length = 0;
    const { host, renamed } = homeHost('page.html', 'newpage', ['page.html']);
    await host.confirmRename();
    assert.deepEqual(renamed, ['page.html>newpage.html']);
  } });
  cases.push({ name: 'library rename to the same normalized name is a silent no-op', async body() {
    toasts.length = 0;
    const { host, renamed } = homeHost('old.md', 'old', ['old.md']);
    await host.confirmRename();
    assert.equal(renamed.length, 0);
    assert.deepEqual(toasts, []);
  } });
};
