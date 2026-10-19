import { MuLogger } from '../../common/MuLogger';
import { common } from '@kit.AbilityKit';
import { HomeEnvironment } from './HomeEnvironment';
import { router, promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { DocumentImportService } from '../../services/DocumentImportService';
import { DocumentIntake } from '../../domain/document/DocumentIntake';
import { RecentFileList, RecentEntry } from '../../domain/document/RecentFileList';
import { LibrarySearch, LibraryDoc } from '../../domain/document/LibrarySearch';
import { FindOptions } from '../../domain/editor/FindReplaceEngine';
import { ThemeMode } from '../../domain/settings/AppSettings';
import { AppTheme } from '../../common/AppTheme';
import { Breakpoint, watchBreakpoints, unwatchBreakpoints, bpOf } from '../../common/Breakpoints';
import { UIContext } from '@kit.ArkUI';
import { HomeState } from './HomeState';
export class HomeController {
  env: HomeEnvironment;
  state: HomeState;
  uiContext: UIContext;
  constructor(state: HomeState, uiContext: UIContext, ctx: common.UIAbilityContext) { this.state = state; this.uiContext = uiContext; this.env = new HomeEnvironment(ctx); }
  async receiveDrop(event: DragEvent): Promise<void> {
    if (this.state.dropBusy) { promptAction.showToast({ message: '正在读取文件，请稍候再拖入' }); return; }
    this.state.dropBusy = true;
    try {
      const id = await new DocumentImportService(this.env.ctx,
        (key: string) => this.uiContext.getDragController().cancelDataLoading(key)).receive(event);
      if (!this.env.active) { return; }
      promptAction.showToast({ message: DocumentIntake.isHtml(id) ? '已导入 HTML 副本，只读预览' : '已导入“我的文档”，编辑的是副本' });
      AppStorage.setOrCreate('pendingOpenUri', id);
    } catch (e) {
      MuLogger.info('[拖入] 文件获取失败');
      promptAction.showToast({ message: String(e).replace(/^Error: /, '') });
    } finally { this.state.dropBusy = false; }
  }

  consumeExternalOpen(): void {
    if (this.env.pendingOpenUri.length === 0 || router.getState().name !== 'HomePage') { return; }
    const uri = this.env.pendingOpenUri;
    this.env.pendingOpenUri = '';
    router.pushUrl({ url: DocumentIntake.page(uri), params: DocumentIntake.route(uri) }).catch(() => {
      MuLogger.info('[打开] 无法进入编辑页，请重新打开文件');
      promptAction.showToast({ message: '打开失败，请重新选择文件' });
    });
  }

  aboutToAppear(): void {
    this.env.active = true;
    this.state.bp = bpOf();
    this.env.bpListeners = watchBreakpoints((bp: Breakpoint) => {
      this.state.bp = bp;
    });
    this.applyTheme();
    this.refresh();
    this.refreshRecovery();
    this.refreshLibrary();
  }

  aboutToDisappear(): void {
    this.env.active = false;
    unwatchBreakpoints(this.env.bpListeners);
    this.env.bpListeners = [];
    if (this.env.searchTimer >= 0) { clearTimeout(this.env.searchTimer); this.env.searchTimer = -1; }
  }

  onPageShow(): void {
    this.env.active = true;
    this.consumeExternalOpen();
    this.state.bp = bpOf();
    this.applyTheme();
    this.refresh();
    this.refreshRecovery();
    this.refreshLibrary();
  }

  applyTheme(): void {
    this.env.settings.load().then((s) => {
      this.state.pal = AppTheme.of(s.theme === ThemeMode.DARK);
    }).catch(() => {
    });
  }

  async refreshRecovery(): Promise<void> {
    try {
      this.state.draftCount = this.env.draftStore.listAll().length;
    } catch (e) {
      this.state.draftCount = 0;
    }
  }

  goRecovery(): void {
    router.pushUrl({ url: 'pages/RecoveryPage' });
  }

  goSettings(): void {
    router.pushUrl({ url: 'pages/SettingsPage' });
  }

  async refresh(): Promise<void> {
    const entries = await this.env.meta.loadRecent();
    // C3-4：固定项排最前，其余按时间倒序
    this.state.recent = new RecentFileList(entries).snapshot().sort((a: RecentEntry, b: RecentEntry): number => {
      if (a.pinned !== b.pinned) {
        return a.pinned ? -1 : 1;
      }
      return b.lastOpenedAt - a.lastOpenedAt;
    });
    MuLogger.info(`[最近] ${this.state.recent.length} 条`);
  }

  async refreshLibrary(): Promise<void> {
    try {
      const names = this.env.fileSource.listLibrary();
      this.state.libraryFiles = names;
      this.state.trashFiles = this.env.fileSource.listTrash();
      MuLogger.info(`[资料库] ${names.length} 个文档`);
    } catch (e) {
      MuLogger.info(`[资料库] 读取失败：${JSON.stringify(e)}`);
    }
  }

  goEditor(): void {
    router.pushUrl({ url: 'pages/EditorPage' });
  }

  goEditorWith(name: string): void {
    const params: ESObject = { name: name } as ESObject;
    router.pushUrl({ url: DocumentIntake.page(name), params: params });
  }

  goEditorWithUri(uri: string): void {
    const params: ESObject = { uri: uri } as ESObject;
    router.pushUrl({ url: DocumentIntake.page(uri), params: params });
  }

  openRecent(item: RecentEntry): void {
    // 外部 URI 记录走 uri 通道（临时授权可能已失效，EditorPage 有失败路径）
    if (item.documentId.startsWith('library/')) {
      this.goEditorWith(item.documentId);
    } else {
      this.goEditorWithUri(item.documentId);
    }
  }

  openLibraryFile(): void {
    this.refreshLibrary().then(() => {
      this.state.pickingFile = true;
    });
  }

  async openExternalFile(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker(this.env.ctx);
      const result: Array<string> = await documentPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.md', '.markdown', '.txt', '.html', '.htm'],
      });
      if (result.length === 0) {
        return; // 用户取消
      }
      this.goEditorWithUri(result[0]);
    } catch (e) {
      MuLogger.info(`[打开] 选择器失败：${JSON.stringify(e)}`);
    }
  }

  libraryRowMenu(name: string): void {
    const that = this;
    promptAction.showActionMenu({
      title: name,
      buttons: [
        { text: '重命名', color: that.state.pal.TEXT },
        { text: '删除（移入回收站）', color: that.state.pal.DANGER },
      ],
    }).then((r: promptAction.ActionMenuSuccessResponse) => {
      if (r.index === 0) {
        that.state.renamingFrom = name;
        that.state.renameText = name;
      } else if (r.index === 1) {
        that.confirmDelete(name);
      }
    });
  }

  async confirmRename(): Promise<void> {
    const oldName = this.state.renamingFrom;
    let newName = this.state.renameText.trim();
    this.state.renamingFrom = '';
    if (oldName.length === 0 || newName.length === 0 || newName === oldName) {
      return;
    }
    if (DocumentIntake.isHtml(oldName)) {
      if (!DocumentIntake.isHtml(newName)) { newName += oldName.substring(oldName.lastIndexOf('.')); }
    } else if (!newName.endsWith('.md')) {
      newName = `${newName}.md`;
    }
    if (newName.indexOf('/') >= 0 || this.env.fileSource.listLibrary().indexOf(newName) !== -1) {
      promptAction.showToast({ message: '名称不可用或已存在' });
      return;
    }
    if (this.env.fileSource.renameLibrary(oldName, newName)) {
      try {
        const entries = await this.env.meta.loadRecent();
        const list = new RecentFileList(entries);
        list.remove(`library/${oldName}`);
        list.touch(`library/${newName}`, Date.now());
        await this.env.meta.saveRecent(list.snapshot());
      } catch (e) {
        // 元数据失败不阻塞文件操作
      }
      this.refresh();
      this.refreshLibrary();
      if (this.state.searchQuery.length > 0) {
        this.runSearch();
      }
      promptAction.showToast({ message: `已重命名为 ${newName}` });
    } else {
      promptAction.showToast({ message: '重命名失败' });
    }
  }

  scheduleSearch(): void {
    if (this.env.searchTimer >= 0) {
      clearTimeout(this.env.searchTimer);
    }
    this.env.searchTimer = setTimeout(() => {
      this.env.searchTimer = -1;
      this.runSearch();
    }, 300);
  }

  async runSearch(): Promise<void> {
    const q = this.state.searchQuery.trim();
    if (q.length === 0) {
      this.state.searchResults = [];
      this.state.searchBusy = false;
      return;
    }
    this.state.searchBusy = true;
    try {
      const docs: LibraryDoc[] = [];
      const names = this.env.fileSource.listLibrary();
      for (const name of names) {
        try {
          const src: ESObject = { kind: 'internal', relativePath: `library/${name}` } as ESObject;
          const r = await this.env.fileSource.read(src);
          docs.push({ name: name, content: r.content });
        } catch (e) {
          // 单篇读取失败跳过
        }
      }
      const opts: FindOptions = { caseSensitive: false, wholeWord: false };
      if (this.env.active && q === this.state.searchQuery.trim()) {
        this.state.searchResults = LibrarySearch.search(docs, q, opts);
      }
    } finally {
      if (this.env.active && q === this.state.searchQuery.trim()) { this.state.searchBusy = false; }
    }
  }

  restoreFromTrash(trashName: string): void {
    const restored = this.env.fileSource.restoreTrash(trashName);
    if (restored.length > 0) {
      this.refreshLibrary();
      this.refresh();
      promptAction.showToast({ message: `已恢复为 ${restored}` });
    } else {
      promptAction.showToast({ message: '恢复失败' });
    }
  }

  goEditorWithResult(name: string): void {
    this.goEditorWith(`library/${name}`);
  }

  confirmDelete(name: string): void {
    const that = this;
    AlertDialog.show({
      title: '删除文档',
      message: `「${name}」将移入回收站（应用私有目录），确定删除？`,
      primaryButton: {
        value: '删除',
        fontColor: that.state.pal.DANGER,
        action: () => {
          that.doDelete(name);
        },
      },
      secondaryButton: {
        value: '取消',
        action: () => {
        },
      },
    });
  }

  async doDelete(name: string): Promise<void> {
    if (this.env.fileSource.trashLibrary(name)) {
      try {
        const entries = await this.env.meta.loadRecent();
        const list = new RecentFileList(entries);
        list.remove(`library/${name}`);
        await this.env.meta.saveRecent(list.snapshot());
      } catch (e) {
        // 元数据失败不阻塞文件操作
      }
      this.refresh();
      this.refreshLibrary();
      if (this.state.searchQuery.length > 0) {
        this.runSearch();
      }
      promptAction.showToast({ message: `已删除 ${name}` });
    } else {
      promptAction.showToast({ message: '删除失败' });
    }
  }

  fmtTime(ms: number): string {
    const d = new Date(ms);
    const hh = `${d.getHours()}`.padStart(2, '0');
    const mm = `${d.getMinutes()}`.padStart(2, '0');
    return `${d.getMonth() + 1}/${d.getDate()} ${hh}:${mm}`;
  }

  trashDisplayName(trashName: string): string {
    const dot = trashName.lastIndexOf('.');
    return dot > 0 ? trashName.substring(0, dot) : trashName;
  }

  recentRowMenu(item: RecentEntry): void {
    const that = this;
    promptAction.showActionMenu({
      title: RecentFileList.displayName(item.documentId),
      buttons: [
        { text: item.pinned ? '取消固定' : '固定到顶部', color: that.state.pal.TEXT },
      ],
    }).then((r: promptAction.ActionMenuSuccessResponse) => {
      if (r.index === 0) {
        that.togglePin(item.documentId);
      }
    });
  }

  async togglePin(docId: string): Promise<void> {
    try {
      const entries = await this.env.meta.loadRecent();
      const list = new RecentFileList(entries);
      const cur = entries.find((e: RecentEntry): boolean => e.documentId === docId);
      list.setPinned(docId, !(cur?.pinned === true));
      await this.env.meta.saveRecent(list.snapshot());
      this.refresh();
    } catch (e) {
      promptAction.showToast({ message: '操作失败' });
    }
  }

}
