import { MuLogger } from '../../common/MuLogger';
import { window, KeyboardAvoidMode } from '@kit.ArkUI';
import { SafeAreaPolicy } from '../../domain/editor/SafeAreaPolicy';

/** Owns all window listeners. Insets exclude the keyboard, which ArkUI RESIZE owns. */
export class WindowViewportAdapter {
  private win: window.Window | undefined = undefined;
  private immersive: boolean = false;
  private avoidChanged = (): void => { this.updateInsets(); this.publishCaption(); };
  private sizeChanged = (): void => { this.updateInsets(); this.publishCaption(); };
  private captionChanged = (): void => { this.publishCaption(); };
  private keyboardChanged = (height: number): void => {
    AppStorage.setOrCreate('keyboardVisible', height > 0);
    MuLogger.info(`keyboard visibility=${String(height > 0)}`);
  };

  async attach(win: window.Window): Promise<void> {
    this.detach();
    this.win = win;
    AppStorage.setOrCreate('keyboardVisible', false);
    try {
      await win.setWindowLayoutFullScreen(true);
      if (this.win !== win) { return; }
      this.immersive = true;
      if (!this.publishInsets()) { throw new Error('cannot read safe insets'); }
      win.on('avoidAreaChange', this.avoidChanged);
      win.on('windowSizeChange', this.sizeChanged);
      win.on('keyboardHeightChange', this.keyboardChanged);
      win.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      MuLogger.info('safe insets active; keyboard mode RESIZE');
    } catch (error) {
      MuLogger.error(`viewport setup failed: ${String(error)}`);
      // If native inset acquisition is unavailable, use the system's non-immersive safe layout.
      await this.fallback(win);
    }
    if (this.win !== win) { return; }
    try {
      win.setWindowDecorVisible(false);
      this.publishCaption();
      win.on('windowTitleButtonRectChange', this.captionChanged);
    } catch (error) { MuLogger.info(`caption controls unavailable: ${String(error)}`); }
  }

  private updateInsets(): void {
    const win = this.win;
    if (win !== undefined && this.immersive && !this.publishInsets()) { this.fallback(win); }
  }

  private async fallback(win: window.Window): Promise<void> {
    this.immersive = false;
    try { await win.setWindowLayoutFullScreen(false); }
    catch (error) { MuLogger.error(`safe layout fallback failed: ${String(error)}`); }
    if (this.win === win) { this.clearInsets(); }
  }

  private publishInsets(): boolean {
    const win = this.win;
    if (win === undefined) { return false; }
    try {
      const rect = win.getWindowProperties().windowRect;
      const unit = win.getUIContext().px2vp(1);
      const insets = SafeAreaPolicy.resolve([
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM),
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT),
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR),
      ], rect.width, rect.height, 1 / unit);
      AppStorage.setOrCreate('safeTop', insets.top);
      AppStorage.setOrCreate('safeBottom', insets.bottom);
      AppStorage.setOrCreate('safeLeft', insets.left);
      AppStorage.setOrCreate('safeRight', insets.right);
      MuLogger.info(`insets vp=${JSON.stringify(insets)}`);
      return true;
    } catch (error) {
      MuLogger.error(`inset update failed: ${String(error)}`);
      return false;
    }
  }

  private publishCaption(): void {
    const win = this.win;
    if (win === undefined) { return; }
    try {
      const rect = win.getTitleButtonRect(); // TitleButtonRect is already vp.
      const top = AppStorage.get<number>('safeTop') ?? 0;
      const right = AppStorage.get<number>('safeRight') ?? 0;
      AppStorage.setOrCreate('titleControlsBottom', rect.width > 0 ? Math.max(0, rect.top + rect.height - top) : 0);
      AppStorage.setOrCreate('titleControlsWidth', rect.width > 0 ? Math.max(0, rect.right + rect.width - right) : 0);
    } catch (error) { MuLogger.info(`caption update unavailable: ${String(error)}`); }
  }

  private clearInsets(): void {
    for (const key of ['safeTop', 'safeBottom', 'safeLeft', 'safeRight']) { AppStorage.setOrCreate(key, 0); }
  }

  detach(): void {
    const win = this.win;
    this.win = undefined;
    this.immersive = false;
    if (win !== undefined) {
      try { win.off('avoidAreaChange', this.avoidChanged); } catch (error) { this.noteRelease(error); }
      try { win.off('windowSizeChange', this.sizeChanged); } catch (error) { this.noteRelease(error); }
      try { win.off('keyboardHeightChange', this.keyboardChanged); } catch (error) { this.noteRelease(error); }
      try { win.off('windowTitleButtonRectChange', this.captionChanged); } catch (error) { this.noteRelease(error); }
    }
    this.clearInsets();
    AppStorage.setOrCreate('keyboardVisible', false);
  }

  private noteRelease(error: Object): void { MuLogger.info(`listener release: ${String(error)}`); }
}
