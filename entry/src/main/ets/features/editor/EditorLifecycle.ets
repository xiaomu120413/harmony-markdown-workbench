import { MuLogger } from '../../common/MuLogger';
import { SaveState } from '../../domain/recovery/SaveStateMachine';
import { ViewModePolicy } from '../../domain/editor/ViewModePolicy';
import { RecentFileList } from '../../domain/document/RecentFileList';
import { AppTheme } from '../../common/AppTheme';
import { RecentEntry } from '../../domain/document/RecentFileList';
import { Breakpoint, watchBreakpoints, unwatchBreakpoints } from '../../common/Breakpoints';
import { AppSettings, ThemeMode, DefaultView } from '../../domain/settings/AppSettings';
import { EditorController } from './EditorController';
export class EditorLifecycle {
  private host: EditorController;
  constructor(host: EditorController) { this.host = host; }

  onCheckpointRequest(): void {
    if (this.host.isActive()) { this.host.protectDraft(); }
  }

  aboutToAppear(): void {
    this.host.env.disposed = false;
    this.host.env.bpListeners = watchBreakpoints((bp: Breakpoint) => {
      this.host.state.bp = bp;
      // 断点变化归一化：phone 档无分屏（ViewModePolicy）
      this.host.state.viewMode = ViewModePolicy.normalize(this.host.state.viewMode, bp);
      if (bp === 'phone') { this.host.state.fileMenuVisible = false; this.host.state.outlineVisible = false; }
      else { this.host.state.fileSheetVisible = false; }
    });
    // 编排器延迟创建：deps 闭包依赖组件方法（字段初始化器内不能引用 this）
    this.host.env.coordinator = this.host.createSaveCoordinator();
    this.host.env.bridgeSink = (raw: string): void => {
      const env = this.host.env.bridge.parseEvent(raw);
      if (env === undefined) {
        return;
      }
      if (env.type === 'edit') {
        if (env.payload.s !== this.host.env.activeSession) { return; }
        // 用户输入（打字/粘贴/IME/撤销重做）：进入 DIRTY 并调度防抖保存与预览同步
        const len = env.payload.len as number | undefined;
        if (len !== undefined) {
          this.host.state.docLength = len;
        }
        const ln = env.payload.line as number | undefined;
        const col = env.payload.col as number | undefined;
        if (ln !== undefined) {
          this.host.state.cursorLine = ln;
        }
        if (col !== undefined) {
          this.host.state.cursorCol = col;
        }
        const c = this.host.env.coordinator;
        if (c !== undefined) {
          // A1：编辑事件携带版本 → 保存完成只确认快照版本
          const ver = env.payload.v as number | undefined;
          if (ver !== undefined) {
            c.onEdit(Date.now(), ver);
          } else {
            c.onEdit(Date.now());
          }
          this.host.state.saveState = c.state;
        }
        this.host.scheduleDocSync();
        return;
      }
      if (env.type === 'command') {
        // C4：快捷键 → 统一命令（与按钮同一路径）
        const action = env.payload.action as string | undefined;
        if (action === 'save') {
          this.host.save();
        } else if (action === 'find') {
          if (this.host.state.findVisible) {
            this.host.state.findVisible = false;
          } else {
            this.host.openFind();
          }
        } else if (action === 'outline') {
          this.host.toggleOutline();
        } else if (action === 'bold') {
          this.host.applyCommand('bold');
        } else if (action === 'italic') {
          this.host.applyCommand('italic');
        }
        return;
      }
      if (env.type === 'editorScroll') {
        // D1：编辑器滚动 → 预览同步（分屏时；防回环：仅编辑器侧触发）
        if (this.host.state.viewMode === DefaultView.SPLIT && this.host.env.previewReady) {
          const line = env.payload.line as number | undefined;
          if (line !== undefined) {
            this.host.runJsValue('window.__editorApi.getSnapshot();').then((md: string) => {
              const js = `window.__previewApi.scrollToLine(${line}, ${JSON.stringify(md)});`;
              this.host.env.previewController.runJavaScript(js);
            });
          }
        }
        return;
      }
      if (env.type === 'cursor') {
        // 光标移动（点击/方向键）：状态栏行列更新
        const ln = env.payload.line as number | undefined;
        const col = env.payload.col as number | undefined;
        if (ln !== undefined) {
          this.host.state.cursorLine = ln;
        }
        if (col !== undefined) {
          this.host.state.cursorCol = col;
        }
        return;
      }
      if (!this.host.env.bridge.isFirstResponse(env.id)) {
        return;
      }
      MuLogger.info(`[event] ${env.type}`);
    };
    this.host.env.flushTimer = setInterval(() => {
      const drained = this.host.env.bridgeMessages.slice();
      this.host.env.bridgeMessages = [];
      for (let i = 0; i < drained.length; i++) {
        if (this.host.env.bridgeSink !== undefined) {
          this.host.env.bridgeSink(drained[i]);
        }
      }
      if (drained.some((raw: string): boolean => raw.includes('"edit"'))) {
        this.host.protectDraft();
      }
    }, 500);
    // 自动保存检查（M4-01：防抖由 SaveScheduler 负责，轮询只触发到期保存；
    // autoSave 设置关闭时跳过自动保存，手动保存仍可用——M5-03）
    this.host.env.saveTimer = setInterval(() => {
      const c = this.host.env.coordinator;
      if (c === undefined || this.host.state.deliveryBusy || !this.host.env.appSettings.autoSave) {
        return;
      }
      c.tick(Date.now()).then((ran: boolean) => {
        if (!this.host.isActive() || c !== this.host.env.coordinator) { return; }
        if (ran) {
          this.host.state.saveState = c.state;
          if (c.state === SaveState.ERROR) {
            MuLogger.info('[自动保存] 失败，保留未保存内容');
          }
        }
      });
    }, 500);
    this.host.resolveRouteParams();
    this.host.applyAppSettings();
    this.host.initSidebar();
  }

  applyAppSettings(preserveView: boolean = false): void {
    this.host.env.settings.load().then((s: AppSettings) => {
      if (!this.host.isActive()) { return; }
      this.host.env.appSettings = s;
      if (!preserveView) {
        this.host.state.viewMode = ViewModePolicy.resolveInitial(this.host.state.bp, s.defaultView);
      }
      this.host.enforceWorkspaceBudget();
      this.host.state.pal = AppTheme.of(s.theme === ThemeMode.DARK);
      this.host.applyEditorStyle();
      this.host.applyPreviewStyle();
    }).catch((e: ESObject) => {
      MuLogger.info(`[设置] 读取失败：${JSON.stringify(e)}`);
    });
  }

  applyEditorStyle(): void {
    const s = this.host.env.appSettings;
    const dark = s.theme === ThemeMode.DARK;
    this.host.runJsValue(`window.__editorApi.setTheme(${dark});`);
    this.host.runJsValue(`window.__editorApi.setFontSize(${s.fontSize});`);
    this.host.runJsValue(`window.__editorApi.setWrap(${s.wrap});`);
    this.host.runJsValue(`window.__editorApi.setLineNumbers(${s.lineNumbers});`);
  }

  applyPreviewStyle(): void {
    if (!this.host.env.previewReady) {
      return;
    }
    const dark = this.host.env.appSettings.theme === ThemeMode.DARK;
    this.host.env.previewController.runJavaScript(`window.__previewApi.setDark(${dark});`);
    this.host.env.previewController.runJavaScript(`window.__previewApi.setFontSize(${this.host.env.appSettings.fontSize});`);
  }

  initSidebar(): void {
    this.host.env.meta.loadSidebarPreferredOpen().then((open: boolean) => {
      this.host.state.sidebarVisible = open && this.host.state.bp !== 'phone';
      this.host.enforceWorkspaceBudget();
    }).catch(() => {
      this.host.state.sidebarVisible = this.host.state.bp !== 'phone';
      this.host.enforceWorkspaceBudget();
    });
    this.host.refreshSidebarData();
  }

  refreshSidebarData(): void {
    this.host.state.sidebarLibrary = this.host.env.internal.listLibrary();
    this.host.env.meta.loadRecent().then((entries: RecentEntry[]) => {
      this.host.state.sidebarRecent = new RecentFileList(entries).snapshot();
    }).catch(() => {
      this.host.state.sidebarRecent = [];
    });
  }

  toggleSidebar(): void {
    this.host.state.sidebarVisible = !this.host.state.sidebarVisible;
    this.host.enforceWorkspaceBudget();
    this.host.env.meta.saveSidebarPreferredOpen(this.host.state.sidebarVisible);
    this.host.refreshSidebarData();
  }

  aboutToDisappear(): void {
    this.host.env.disposed = true;
    this.host.env.documentRead = undefined;
    unwatchBreakpoints(this.host.env.bpListeners);
    this.host.env.bpListeners = [];
    if (this.host.env.flushTimer >= 0) {
      clearInterval(this.host.env.flushTimer);
      this.host.env.flushTimer = -1;
    }
    if (this.host.env.saveTimer >= 0) {
      clearInterval(this.host.env.saveTimer);
      this.host.env.saveTimer = -1;
    }
    if (this.host.env.previewTimer >= 0) {
      clearTimeout(this.host.env.previewTimer);
      this.host.env.previewTimer = -1;
    }
    this.host.env.bridgeSink = undefined;
    this.host.env.bridgeMessages = [];
  }
}
