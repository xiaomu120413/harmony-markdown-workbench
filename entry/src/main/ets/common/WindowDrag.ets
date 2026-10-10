import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-WIN';

/**
 * 应用内窗口拖动热区（系统标题栏隐藏后由内容区接管移动窗口）。
 * 在 TouchType.Down 时调用：系统接管后续拖动手势，应用无需自行处理移动。
 * 设备/形态不支持（如手机全屏无自由窗口）时静默忽略。
 */
export function beginWindowMove(ctx: common.UIAbilityContext): void {
  try {
    window.getLastWindow(ctx).then((w: window.Window) => {
      w.startMoving().catch((e: ESObject) => {
        hilog.info(DOMAIN, TAG, 'startMoving rejected: %{public}s', JSON.stringify(e));
      });
    }).catch((e: ESObject) => {
      hilog.info(DOMAIN, TAG, 'getLastWindow failed: %{public}s', JSON.stringify(e));
    });
  } catch (e) {
    hilog.info(DOMAIN, TAG, 'startMoving unavailable');
  }
}
