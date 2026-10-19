import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { SafePage } from '../components/SafePage';
import { ControlStyle } from '../common/ControlStyle';
import { WebDragStyle } from '../common/WebDragStyle';
import { beginWindowMove } from '../common/WindowDrag';
import { DocumentOpenParams } from '../domain/document/DocumentIntake';
import { HtmlPreviewState, HtmlPreviewViewModel } from '../features/preview/HtmlPreviewViewModel';

@Entry
@Component
struct HtmlPreviewPage {
  @State state: HtmlPreviewState = new HtmlPreviewState();
  @StorageProp('titleControlsBottom') captionBottom: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private actions: HtmlPreviewViewModel = new HtmlPreviewViewModel(this.state,
    getContext(this) as common.UIAbilityContext, this.controller);
  aboutToAppear(): void {
    this.actions.loadTheme();
    this.actions.load(router.getParams() as DocumentOpenParams);
  }
  aboutToDisappear(): void { this.actions.dispose(); }
  build() {
    Column() { SafePage() {
      Column({ space: 0 }) {
        Row({ space: 10 }) {
          Button('返回', { type: ButtonType.Normal })
            .attributeModifier(new ControlStyle(this.state.pal, 'quiet'))
            .onClick(() => router.back())
          Text(this.state.title).fontSize(16).fontColor(this.state.pal.TEXT)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) { beginWindowMove(getContext(this) as common.UIAbilityContext); }
            })
        }.width('100%').padding(12)
        Text(this.state.status).fontSize(12).fontColor(this.state.pal.TEXT_SUB)
          .width('100%').padding({ left: 16, right: 16, bottom: 10 })
        Web({ src: 'about:blank', controller: this.controller })
          .javaScriptAccess(false).fileAccess(false).blockNetwork(true)
          .domStorageAccess(false).databaseAccess(false).geolocationAccess(false)
          .onOverrideUrlLoading((request: WebResourceRequest): boolean => {
            const url = request.getRequestUrl();
            return url !== 'about:blank' && url !== 'https://mumark.invalid/';
          })
          .onPageEnd(() => this.actions.attach())
          .attributeModifier(new WebDragStyle())
          .width('100%').layoutWeight(1)
      }.width('100%').height('100%').padding({ top: this.captionBottom })
        .backgroundColor(this.state.pal.BG)
        .onDrop((event: DragEvent) => this.actions.receiveDrop(event,
          (key: string) => this.getUIContext().getDragController().cancelDataLoading(key)), { disableDataPrefetch: true })
    } }.width('100%').height('100%')
  }
}
