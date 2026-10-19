import { HomeLibraryPanel } from './HomeLibraryPanel';
import { ControlStyle } from '../../common/ControlStyle';
import { RecentFileList } from '../../domain/document/RecentFileList';
import { HomeState } from './HomeState';
import { HomeController } from './HomeController';

@Component
export struct HomeWelcome {
  @ObjectLink state: HomeState;
  @Require actions: HomeController;
  @Builder
  primaryBtn(label: string, action: () => void) {
    Button(label, { type: ButtonType.Normal })
      .width('100%')
      .attributeModifier(new ControlStyle(this.state.pal, 'primary'))
      .onClick(() => action())
  }
  @Builder
  welcomePanel() {
    Column({ space: 0 }) {
      Blank().height(120)

      Text('开始写作')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.state.pal.TEXT)
      Text('打开已有文档，或新建一份 Markdown。')
        .fontSize(13)
        .fontColor(this.state.pal.TEXT_FAINT)
        .padding({ top: 6, bottom: 36 })

      Button('新建文档', { type: ButtonType.Normal })
        .width(180)
        .attributeModifier(new ControlStyle(this.state.pal, 'secondary'))
        .onClick(() => this.actions.goEditor())

      Text('或从左侧打开最近的文档')
        .fontSize(12)
        .fontColor(this.state.pal.TEXT_FAINT)
        .padding({ top: 12 })

      if (this.state.recent.length > 0) {
        Text(`上次编辑 · ${RecentFileList.displayName(this.state.recent[0].documentId)} · ${this.actions.fmtTime(this.state.recent[0].lastOpenedAt)}`)
          .fontSize(12)
          .fontColor(this.state.pal.TEXT_SUB)
          .padding({ top: 4 })
          .onClick(() => this.actions.openRecent(this.state.recent[0]))
      }

      if (this.state.pickingFile) {
        Blank().height(24)
        HomeLibraryPanel({ state: this.state, actions: this.actions })
      }

      Blank().layoutWeight(1)
    }
    .layoutWeight(1)
    .height('100%')
    .padding(28)
    .backgroundColor(this.state.pal.CONTENT)
    .alignItems(HorizontalAlign.Start)
  }
  build() { this.welcomePanel() }
}
