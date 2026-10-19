import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('checkpointRequest', 0);
    AppStorage.setOrCreate('pendingOpenUri', '');
    AppStorage.setOrCreate('titleControlsBottom', 0);
    AppStorage.setOrCreate('titleControlsWidth', 0);
    this.receiveFile(want);
    hilog.info(DOMAIN, TAG, 'EntryAbility onCreate');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.receiveFile(want);
  }

  private receiveFile(want: Want): void {
    if (!want.uri) { return; }
    if (want.action !== 'ohos.want.action.viewData' || !want.uri.startsWith('file://')) {
      hilog.warn(DOMAIN, TAG, 'unsupported file-open request');
      return;
    }
    const type = want.type ?? '';
    if (!['text/markdown', 'text/x-markdown', 'text/plain', 'general.markdown', 'general.plain-text'].includes(type) &&
      !/\.(md|markdown|txt)(?:\?|$)/i.test(want.uri)) {
      hilog.warn(DOMAIN, TAG, 'unsupported file type');
      return;
    }
    AppStorage.setOrCreate('pendingOpenUri', want.uri);
    hilog.info(DOMAIN, TAG, 'external file queued');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 沉浸式：扩展到状态栏区域
    windowStage.getMainWindow().then((win: window.Window) => {
      win.setWindowLayoutFullScreen(true);
    });
    windowStage.loadContent('pages/HomePage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'HomePage loaded');
      // 隐藏 DecorBar 后仍保留系统三键；发布其实际高度供窄窗避让。
      // 窗口拖动由应用内热区（页面标题，startMoving）接管。
      // 须在 loadContent 生效后调用；不支持的形态（手机全屏等）静默降级。
      windowStage.getMainWindow().then((win: window.Window) => {
        try {
          win.setWindowDecorVisible(false);
          const updateTitleControls = (rect: window.TitleButtonRect): void => {
            AppStorage.setOrCreate('titleControlsBottom', rect.width > 0 ? rect.top + rect.height : 0);
            AppStorage.setOrCreate('titleControlsWidth', rect.width > 0 ? rect.right + rect.width : 0);
          };
          updateTitleControls(win.getTitleButtonRect());
          win.on('windowTitleButtonRectChange', updateTitleControls);
          hilog.info(DOMAIN, TAG, 'window decor hidden');
        } catch (e) {
          hilog.info(DOMAIN, TAG, 'setWindowDecorVisible unavailable: %{public}s', JSON.stringify(e));
        }
      });
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onForeground');
  }

  onBackground(): void {
    AppStorage.setOrCreate('checkpointRequest', (AppStorage.get<number>('checkpointRequest') ?? 0) + 1);
    hilog.info(DOMAIN, TAG, 'EntryAbility onBackground');
  }
}
