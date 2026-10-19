import { MuLogger } from '../common/MuLogger';
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { WindowViewportAdapter } from '../infrastructure/window/WindowViewportAdapter';

export default class EntryAbility extends UIAbility {
  private viewport: WindowViewportAdapter = new WindowViewportAdapter();
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('checkpointRequest', 0);
    AppStorage.setOrCreate('pendingOpenUri', '');
    AppStorage.setOrCreate('titleControlsBottom', 0);
    AppStorage.setOrCreate('titleControlsWidth', 0);
    this.receiveFile(want);
    MuLogger.info('EntryAbility onCreate');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.receiveFile(want);
  }

  private receiveFile(want: Want): void {
    if (!want.uri) { return; }
    if (want.action !== 'ohos.want.action.viewData' || !want.uri.startsWith('file://')) {
      MuLogger.warn('unsupported file-open request');
      return;
    }
    const type = want.type ?? '';
    if (!['text/markdown', 'text/x-markdown', 'text/plain', 'general.markdown', 'general.plain-text'].includes(type) &&
      !/\.(md|markdown|txt)(?:\?|$)/i.test(want.uri)) {
      MuLogger.warn('unsupported file type');
      return;
    }
    AppStorage.setOrCreate('pendingOpenUri', want.uri);
    MuLogger.info('external file queued');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/HomePage', (err) => {
      if (err.code) {
        MuLogger.error(`Failed to load content: ${JSON.stringify(err)}`);
        return;
      }
      MuLogger.info('HomePage loaded');
      windowStage.getMainWindow().then((win: window.Window) => {
        this.viewport.attach(win);
      }).catch((error: Object) => { MuLogger.error(`main window unavailable: ${String(error)}`); });
    });
  }

  onWindowStageDestroy(): void {
    this.viewport.detach();
    MuLogger.info('EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    MuLogger.info('EntryAbility onForeground');
  }

  onBackground(): void {
    AppStorage.setOrCreate('checkpointRequest', (AppStorage.get<number>('checkpointRequest') ?? 0) + 1);
    MuLogger.info('EntryAbility onBackground');
  }
}
