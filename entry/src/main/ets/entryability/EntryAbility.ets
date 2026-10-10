import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onCreate');
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
      // 隐藏系统标题栏（自由窗口 DecorBar）：应用自定义顶栏成为唯一标题栏，
      // 内容区接管原标题栏空间；窗口拖动由应用内热区（页面标题，startMoving）接管。
      // 须在 loadContent 生效后调用；不支持的形态（手机全屏等）静默降级。
      windowStage.getMainWindow().then((win: window.Window) => {
        try {
          win.setWindowDecorVisible(false);
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
    hilog.info(DOMAIN, TAG, 'EntryAbility onBackground');
  }
}