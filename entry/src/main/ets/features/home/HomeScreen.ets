import { HomeCompact } from './HomeCompact';
import { HomeNavigation } from './HomeNavigation';
import { HomeRecentList } from './HomeRecentList';
import { HomeWelcome } from './HomeWelcome';
import { HomeState } from './HomeState';
import { HomeController } from './HomeController';

@Component
export struct HomeScreen {
  @ObjectLink state: HomeState;
  @Require actions: HomeController;
  @Builder
  phoneTab(label: string, active: boolean, action: () => void) {
    Text(label)
      .fontSize(12)
      .fontWeight(active ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(active ? this.state.pal.PRIMARY : this.state.pal.TEXT_FAINT)
      .textAlign(TextAlign.Center)
      .width('100%')
      .lineHeight(52)
      .onClick(() => action())
      .layoutWeight(1)
      .height(52)
  }
  build() {
    Column() {
      if (this.state.bp === 'phone') {
        HomeCompact({ state: this.state, actions: this.actions })
        Row() {
          this.phoneTab('首页', true, () => {})
          this.phoneTab('编辑', false, () => this.actions.goEditor())
          this.phoneTab('设置', false, () => this.actions.goSettings())
        }
        .width('100%')
        .height(52)
        .backgroundColor(this.state.pal.CONTENT)
        .border({ width: { top: 1 }, color: this.state.pal.DIVIDER })
      } else {
        Row({ space: 0 }) {
          HomeNavigation({ state: this.state, actions: this.actions })
          Divider().vertical(true).height('100%').color(this.state.pal.DIVIDER)
          if (!this.state.recentCollapsed) {
            HomeRecentList({ state: this.state, actions: this.actions })
            Divider().vertical(true).height('100%').color(this.state.pal.DIVIDER)
          }
          if (this.state.bp === 'pc' || this.state.recentCollapsed) {
            HomeWelcome({ state: this.state, actions: this.actions })
          }
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
