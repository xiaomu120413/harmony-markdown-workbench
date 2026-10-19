import { SafePage } from '../components/SafePage';
import { common } from '@kit.AbilityKit';
import { EditorState } from '../features/editor/EditorState';
import { EditorController } from '../features/editor/EditorController';
import { EditorScreen } from '../features/editor/EditorScreen';

@Entry
@Component
struct EditorPage {
  @State state: EditorState = new EditorState();
  private actions: EditorController | undefined = undefined;
  @StorageLink('checkpointRequest') @Watch('checkpointChanged') checkpointRequest: number = 0;
  @StorageLink('pendingOpenUri') @Watch('externalOpenChanged') pendingOpenUri: string = '';
  @StorageLink('titleControlsBottom') @Watch('captionChanged') titleControlsBottom: number = 0;
  @StorageLink('titleControlsWidth') @Watch('captionChanged') titleControlsWidth: number = 0;
  private checkpointChanged(): void { this.actions?.onCheckpointRequest(); }
  private externalOpenChanged(): void { this.actions?.onExternalOpen(); }
  private captionChanged(): void {
    this.state.titleControlsBottom = this.titleControlsBottom;
    this.state.titleControlsWidth = this.titleControlsWidth;
  }
  aboutToAppear(): void {
    this.actions = new EditorController(this.state, this.getUIContext(), getContext(this) as common.UIAbilityContext);
    this.captionChanged();
    this.actions.aboutToAppear();
  }
  aboutToDisappear(): void { this.actions?.aboutToDisappear(); }
  onPageShow(): void { this.actions?.applyAppSettings(true); }
  /** 系统返回键统一走保存保护：有未保存修改时拦截确认，干净时由 goBack 放行。 */
  onBackPress(): boolean {
    if (this.actions === undefined) { return false; }
    this.actions.goBack();
    return true;
  }
  build() {
    if (this.actions !== undefined) {
      SafePage() { EditorScreen({ state: this.state, actions: this.actions }) }
    }
  }
}
