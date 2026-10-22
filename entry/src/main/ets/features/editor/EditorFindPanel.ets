import { KeyCode } from '@kit.InputKit';
import { ControlStyle, ControlMetrics } from '../../common/ControlStyle';
import { EditorState } from './EditorState';
import { EditorController } from './EditorController';

@Component
export struct EditorFindPanel {
  @ObjectLink state: EditorState;
  @Require actions: EditorController;
  private handleEscape(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down || event.keyCode !== KeyCode.KEYCODE_ESCAPE) { return false; }
    this.state.findVisible = false;
    this.actions.env.controller.requestFocus();
    return true;
  }
  @Builder
  panelBtn(label: string, action: () => void) {
    Button(label, { type: ButtonType.Normal })
      .attributeModifier(new ControlStyle(this.state.pal, 'quiet'))
      .width(96)
      .onClick(() => action())
  }
  build() {
      if (this.state.findVisible) {
        Scroll() {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
          TextInput({ placeholder: '查找', text: this.state.findQuery })
            .onKeyPreIme((event: KeyEvent): boolean => this.handleEscape(event))
            .id('editor-find-query')
            .onAppear(() => this.getUIContext().getFocusController().requestFocus('editor-find-query'))
            .fontSize(13)
            .height(ControlMetrics.HEIGHT)
            .padding({ left: 8, right: 8 })
            .backgroundColor(this.state.pal.CARD)
            .borderRadius(ControlMetrics.RADIUS)
            .constraintSize({ minWidth: 120, maxWidth: 220 })
            .onChange((v: string) => {
              this.state.findQuery = v;
              this.actions.refreshFind().then(() => this.actions.locateFirstMatch());
            })
            .onSubmit(() => this.actions.jumpNext())
          TextInput({ placeholder: '替换为', text: this.state.replaceText })
            .onKeyPreIme((event: KeyEvent): boolean => this.handleEscape(event))
            .fontSize(13)
            .height(ControlMetrics.HEIGHT)
            .padding({ left: 8, right: 8 })
            .backgroundColor(this.state.pal.CARD)
            .borderRadius(ControlMetrics.RADIUS)
            .constraintSize({ minWidth: 120, maxWidth: 220 })
            .onChange((v: string) => {
              this.state.replaceText = v;
            })
          Text(this.state.matchCount > 0 ? `${this.state.matchIndex + 1}/${this.state.matchCount}` : '0 命中')
            .fontSize(12)
            .fontColor(this.state.matchCount > 0 ? this.state.pal.PRIMARY : this.state.pal.TEXT_FAINT)
            .padding({ left: 6, right: 6 })
          this.panelBtn('上一个', () => this.actions.jumpPrev())
          this.panelBtn('下一个', () => this.actions.jumpNext())
          this.panelBtn('替换', () => this.actions.replaceCurrent())
          this.panelBtn('全部替换', () => this.actions.replaceAllMatches())
          Row({ space: 4 }) {
            Button('Aa', { type: ButtonType.Normal })
              .attributeModifier(new ControlStyle(this.state.pal, this.state.findCase ? 'selected' : 'quiet'))
              .onClick(() => {
                this.state.findCase = !this.state.findCase;
                this.actions.refreshFind();
              })
            Button('全词', { type: ButtonType.Normal })
              .attributeModifier(new ControlStyle(this.state.pal, this.state.findWord ? 'selected' : 'quiet'))
              .onClick(() => {
                this.state.findWord = !this.state.findWord;
                this.actions.refreshFind();
              })
            Button({ type: ButtonType.Normal }) {
              SymbolGlyph($r('sys.symbol.xmark')).fontSize(20).fontColor([this.state.pal.TEXT])
            }
              .attributeModifier(new ControlStyle(this.state.pal, 'quiet', true)).accessibilityText('关闭')
              .onClick(() => {
                this.state.findVisible = false;
              })
          }
        }
        .width('100%')
        .padding(6)
        .backgroundColor(this.state.pal.CARD)
        .borderRadius(8)
        .border({ width: 1, color: this.state.pal.DIVIDER })
        }.width('100%').constraintSize({ maxHeight: this.state.compactHeight ? 60 : 240 })
          .align(Alignment.TopStart).scrollBar(BarState.Auto)
          .onKeyEvent((event: KeyEvent) => { if (this.handleEscape(event)) { event.stopPropagation(); } })
      }

  }
}
