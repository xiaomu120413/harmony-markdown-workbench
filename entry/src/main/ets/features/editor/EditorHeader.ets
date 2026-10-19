import { EditorFileActions } from './EditorFileActions';
import { ControlStyle, ControlMetrics } from '../../common/ControlStyle';
import { SegBtn } from '../../common/SegBtn';
import { beginWindowMove } from '../../common/WindowDrag';
import { DefaultView } from '../../domain/settings/AppSettings';
import { EditorState } from './EditorState';
import { EditorController } from './EditorController';

@Component
export struct EditorHeader {
  @ObjectLink state: EditorState;
  @Require actions: EditorController;
  @Builder
  phoneHeader() {
    if (this.state.titleControlsBottom > 0) {
      Blank().height(this.state.titleControlsBottom).width('100%')
        .onTouch((e: TouchEvent) => { if (e.type === TouchType.Down) { beginWindowMove(this.actions.env.ctx); } })
    }
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20).fontColor([this.state.pal.TEXT])
      }.attributeModifier(new ControlStyle(this.state.pal, 'quiet', true))
        .accessibilityText('返回首页').onClick(() => this.actions.goBack())
      Column({ space: 2 }) {
        Text(this.state.docTitle).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.state.pal.TEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.state.saveLabel).fontSize(12).fontColor(this.actions.saveStatusColor())
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button('保存', { type: ButtonType.Normal })
        .attributeModifier(new ControlStyle(this.state.pal, 'primary')).onClick(() => this.actions.save())
      EditorFileActions({ state: this.state, actions: this.actions })
    }.width('100%')
    if (!this.state.compactHeight) {
    Row({ space: 6 }) {
      SegBtn({ label: '编辑', active: this.state.viewMode === DefaultView.EDIT, pal: this.state.pal, action: () => this.actions.setViewMode(DefaultView.EDIT) })
      SegBtn({ label: '预览', active: this.state.viewMode === DefaultView.PREVIEW, pal: this.state.pal, action: () => this.actions.setViewMode(DefaultView.PREVIEW) })
      Blank()
      Button('大纲', { type: ButtonType.Normal })
        .attributeModifier(new ControlStyle(this.state.pal, 'quiet'))
        .onClick(() => { this.actions.toggleOutline(); })
      Button('查找', { type: ButtonType.Normal })
        .attributeModifier(new ControlStyle(this.state.pal, 'quiet'))
        .onClick(() => { this.actions.openFind(); })
    }.width('100%')
    }
  }
  @Builder
  wideHeader() {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20).fontColor([this.state.pal.TEXT])
      }.attributeModifier(new ControlStyle(this.state.pal, 'quiet', true))
        .accessibilityText('返回首页').onClick(() => this.actions.goBack())
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.line_3_horizontal')).fontSize(20).fontColor([this.state.pal.TEXT])
      }.attributeModifier(new ControlStyle(this.state.pal, this.state.sidebarVisible ? 'selected' : 'quiet', true))
        .accessibilityText('文档侧栏').onClick(() => this.actions.toggleSidebar())
      Column({ space: 2 }) {
        Text(this.state.docTitle).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.state.pal.TEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(this.state.saveLabel).fontSize(12).fontColor(this.actions.saveStatusColor())
      }.layoutWeight(1).alignItems(HorizontalAlign.Start).padding({ left: 8 })
        .onTouch((e: TouchEvent) => { if (e.type === TouchType.Down) { beginWindowMove(this.actions.env.ctx); } })
      EditorFileActions({ state: this.state, actions: this.actions })
      Button('保存', { type: ButtonType.Normal })
        .attributeModifier(new ControlStyle(this.state.pal, 'primary')).onClick(() => this.actions.save())
    }.width('100%').height(ControlMetrics.HEIGHT)
      .padding({ right: this.state.titleControlsWidth > 0 ? this.state.titleControlsWidth + 8 : 0 })
  }
  build() { if (this.state.bp === 'phone') { this.phoneHeader() } else { this.wideHeader() } }
}
