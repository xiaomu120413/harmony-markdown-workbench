import { SafePage } from '../components/SafePage';
import { common } from '@kit.AbilityKit';
import { HomeState } from '../features/home/HomeState';
import { HomeController } from '../features/home/HomeController';
import { HomeScreen } from '../features/home/HomeScreen';
@Entry
@Component
struct HomePage {
  @State state: HomeState = new HomeState();
  @StorageProp('colorMode') @Watch('colorModeChanged') colorMode: number = -1;
  private colorModeChanged(): void { this.actions?.applyTheme(); }
  private actions: HomeController | undefined = undefined;
  @StorageLink('pendingOpenUri') @Watch('externalOpenChanged') pendingOpenUri: string = '';
  private externalOpenChanged(): void { this.actions?.consumeExternalOpen(); }
  aboutToAppear(): void {
    this.actions = new HomeController(this.state, this.getUIContext(), getContext(this) as common.UIAbilityContext);
    this.actions.aboutToAppear();
  }
  onPageShow(): void { this.actions?.onPageShow(); }
  aboutToDisappear(): void { this.actions?.aboutToDisappear(); }
  build() { if (this.actions !== undefined) { SafePage() { HomeScreen({ state: this.state, actions: this.actions }) } } }
}
