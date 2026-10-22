import { HomeCompact } from './HomeCompact';
import { HomeNavigation } from './HomeNavigation';
import { HomeWelcome } from './HomeWelcome';
import { HomeState } from './HomeState';
import { HomeController } from './HomeController';

@Component
export struct HomeScreen {
  @ObjectLink state: HomeState;
  @Require actions: HomeController;
  @Builder
  phoneTab(label: string, icon: Resource, active: boolean, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 3 }) {
        SymbolGlyph(icon).fontSize(20).fontColor([active ? this.state.pal.PRIMARY : this.state.pal.TEXT_SUB])
        Text(label).fontSize(11).fontColor(active ? this.state.pal.PRIMARY : this.state.pal.TEXT_SUB)
      }
    }.layoutWeight(1).height(56).backgroundColor(Color.Transparent).borderRadius(0)
      .accessibilityText(label).accessibilitySelected(active).onClick(action)
  }
  build() {
    Column() {
      if (this.state.bp === 'phone') {
        HomeCompact({ state: this.state, actions: this.actions })
        Row() {
          this.phoneTab('文档', $r('sys.symbol.folder'), true, () => {})
          this.phoneTab('新建', $r('sys.symbol.plus'), false, () => this.actions.goEditor())
          this.phoneTab('设置', $r('sys.symbol.gearshape'), false, () => this.actions.goSettings())
        }
        .width('100%')
        .height(56)
        .backgroundColor(this.state.pal.CONTENT)
        .border({ width: { top: 1 }, color: this.state.pal.DIVIDER })
      } else {
        Row({ space: 0 }) {
          HomeNavigation({ state: this.state, actions: this.actions })
          Divider().vertical(true).height('100%').color(this.state.pal.DIVIDER)
          HomeWelcome({ state: this.state, actions: this.actions })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.state.pal.BG)
    .onAreaChange((_old: Area, area: Area) => { this.state.compactHeight = (area.height as number) < 480; })
    .onDrop((event: DragEvent) => { this.actions.receiveDrop(event); }, { disableDataPrefetch: true })
  }
}
