import { ControlStyle, ControlMetrics } from '../../common/ControlStyle';
import { beginWindowMove } from '../../common/WindowDrag';
import { HomeState } from './HomeState';
import { HomeController } from './HomeController';

@Component
export struct HomeNavigation {
  @ObjectLink state: HomeState;
  @Require actions: HomeController;
  @Builder
  navRow(label: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 8 }) {
        Text(label)
          .fontSize(ControlMetrics.FONT)
          .fontColor(this.state.pal.TEXT)
          .layoutWeight(1)
      }.width('100%')
    }
      .attributeModifier(new ControlStyle(this.state.pal)).width('100%')
      .onClick(() => action())
  }
  @Builder
  primaryBtn(label: string, action: () => void) {
    Button(label, { type: ButtonType.Normal })
      .width('100%')
      .attributeModifier(new ControlStyle(this.state.pal, 'primary'))
      .onClick(() => action())
  }
  @Builder
  sideBar() {
    Column({ space: 2 }) {
      Text('木笺')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.state.pal.TEXT)
        .maxLines(1)
        .padding({ top: 6, bottom: 2 })
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) {
            beginWindowMove(this.actions.env.ctx);
          }
        })
      Text('本机 Markdown 文档')
        .fontSize(11)
        .fontColor(this.state.pal.TEXT_FAINT)
        .padding({ bottom: 10 })

      this.primaryBtn('新建文档', () => this.actions.goEditor())

      Column({ space: 0 }) {
        this.navRow('打开文档', () => this.actions.openExternalFile())
        this.navRow('我的文档', () => this.actions.openLibraryFile())
        if (this.state.draftCount > 0) {
          this.navRow(`找回未保存内容（${this.state.draftCount}）`, () => this.actions.goRecovery())
        }
        this.navRow('设置', () => this.actions.goSettings())
      }
      .width('100%')
      .margin({ top: 6 })

      // 最近列表收起/展开（收起后欢迎区占满）
      Row() {
        Text('最近列表')
          .fontSize(12)
          .fontColor(this.state.pal.TEXT_SUB)
        Blank()
        Button(this.state.recentCollapsed ? '展开' : '收起', { type: ButtonType.Normal })
          .attributeModifier(new ControlStyle(this.state.pal, 'quiet'))
          .onClick(() => {
            this.state.recentCollapsed = !this.state.recentCollapsed;
          })
      }
      .width('100%')
      .padding({ top: 14, bottom: 4, left: 14, right: 12 })
    }
    .width(250)
    .height('100%')
    .padding({ left: 8, right: 8, top: 10, bottom: 10 })
    .backgroundColor(this.state.pal.SIDEBAR)
    .alignItems(HorizontalAlign.Start)
  }
  build() { this.sideBar() }
}
