import { HomeLibraryPanel } from './HomeLibraryPanel';
import { HomeRecentList } from './HomeRecentList';
import { ControlStyle } from '../../common/ControlStyle';
import { HomeState } from './HomeState';
import { HomeController } from './HomeController';

/** 宽窗口的文档工作区，首页只有一处新建入口。 */
@Component
export struct HomeWelcome {
  @StorageProp('titleControlsBottom') captionBottom: number = 0;
  @ObjectLink state: HomeState;
  @Require actions: HomeController;
  build() {
    Column({ space: 24 }) {
      Row({ space: 16 }) {
        Column({ space: 6 }) {
          Text(this.state.pickingFile ? '我的文档' : '文档').fontSize(28).fontWeight(FontWeight.Medium)
            .fontColor(this.state.pal.TEXT)
          Text('打开、编辑与整理本机文档').fontSize(13).fontColor(this.state.pal.TEXT_SUB)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('新建文档', { type: ButtonType.Normal })
          .attributeModifier(new ControlStyle(this.state.pal, 'primary')).onClick(() => this.actions.goEditor())
      }.width('100%')
      if (this.state.pickingFile) {
        HomeLibraryPanel({ state: this.state, actions: this.actions }).width('100%').layoutWeight(1)
      } else {
        HomeRecentList({ state: this.state, actions: this.actions }).layoutWeight(1)
      }
    }.layoutWeight(1).height('100%').padding({
      left: this.state.bp === 'pc' ? 32 : 20,
      right: this.state.bp === 'pc' ? 32 : 20,
      top: Math.max(this.state.bp === 'pc' ? 32 : 20, this.captionBottom + 8),
      bottom: this.state.bp === 'pc' ? 32 : 20,
    })
      .backgroundColor(this.state.pal.BG).alignItems(HorizontalAlign.Start)
  }
}
