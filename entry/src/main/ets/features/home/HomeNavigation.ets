import { ControlStyle } from '../../common/ControlStyle';
import { beginWindowMove } from '../../common/WindowDrag';
import { HomeState } from './HomeState';
import { HomeController } from './HomeController';

@Component
export struct HomeNavigation {
  @ObjectLink state: HomeState;
  @Require actions: HomeController;
  @Builder
  navRow(label: string, icon: Resource, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        SymbolGlyph(icon).fontSize(18).fontColor([this.state.pal.TEXT_SUB])
        Text(label).fontSize(14).fontColor(this.state.pal.TEXT).layoutWeight(1).textAlign(TextAlign.Start)
      }.width('100%')
    }.attributeModifier(new ControlStyle(this.state.pal,
      label === '最近文档' && !this.state.pickingFile ? 'selected' : 'quiet')).width('100%')
      .onClick(action)
  }
  build() {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        Image($r('app.media.foreground')).width(32).height(32).borderRadius(8)
        Column({ space: 2 }) {
          Text('木笺').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.state.pal.TEXT)
          Text('MuMark').fontSize(11).fontColor(this.state.pal.TEXT_SUB).letterSpacing(1)
        }.alignItems(HorizontalAlign.Start)
      }.width('100%').padding({ left: 10, top: 8, bottom: 30 })
        .onTouch((event: TouchEvent) => { if (event.type === TouchType.Down) { beginWindowMove(this.actions.env.ctx); } })
      this.navRow('最近文档', $r('sys.symbol.clock'), () => {
        this.state.pickingFile = false; this.state.searchQuery = ''; this.state.searchResults = [];
      })
      this.navRow('打开文档', $r('sys.symbol.folder'), () => this.actions.openExternalFile())
      this.navRow('我的文档', $r('sys.symbol.line_3_horizontal'), () => this.actions.openLibraryFile())
      if (this.state.draftCount > 0) {
        this.navRow(`恢复草稿 · ${this.state.draftCount}`, $r('sys.symbol.clock'), () => this.actions.goRecovery())
      }
      Blank().layoutWeight(1)
      Divider().color(this.state.pal.DIVIDER).margin({ top: 12, bottom: 8 })
      this.navRow('设置', $r('sys.symbol.gearshape'), () => this.actions.goSettings())
      Text('本机文档 · 离线编辑').fontSize(11).fontColor(this.state.pal.TEXT_SUB)
        .padding({ left: 12, top: 8, bottom: 8 }).width('100%')
    }.width(200).height('100%').padding(12).backgroundColor(this.state.pal.SIDEBAR)
      .alignItems(HorizontalAlign.Start)
  }
}
