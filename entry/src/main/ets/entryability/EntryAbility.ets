import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { WindowViewportAdapter } from '../infrastructure/window/WindowViewportAdapter';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB';

export default class EntryAbility extends UIAbility {
  private viewport: WindowViewportAdapter = new WindowViewportAdapter();
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
    windowStage.loadContent('pages/HomePage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'HomePage loaded');
      windowStage.getMainWindow().then((win: window.Window) => {
        this.viewport.attach(win);
      }).catch((error: Object) => { hilog.error(DOMAIN, TAG, 'main window unavailable: %{public}s', String(error)); });
    });
  }

  onWindowStageDestroy(): void {
    this.viewport.detach();
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
