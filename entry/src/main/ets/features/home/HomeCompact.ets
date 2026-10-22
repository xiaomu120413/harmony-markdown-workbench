import { HomeLibraryPanel } from './HomeLibraryPanel';
import { ControlStyle, ControlMetrics } from '../../common/ControlStyle';
import { RecentFileList, RecentEntry } from '../../domain/document/RecentFileList';
import { DocSearchResult } from '../../domain/document/LibrarySearch';
import { beginWindowMove } from '../../common/WindowDrag';
import { HomeState } from './HomeState';
import { HomeController } from './HomeController';

@Component
export struct HomeCompact {
  @StorageProp('titleControlsBottom') captionBottom: number = 0;
  @ObjectLink state: HomeState;
  @Require actions: HomeController;
  @Builder
  recentRow(item: RecentEntry) {
    Row({ space: 0 }) {
      Button({ type: ButtonType.Normal }) {
      Column({ space: 3 }) {
        Text(RecentFileList.displayName(item.documentId))
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.state.pal.TEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(RecentFileList.location(item.documentId))
          .fontSize(12).fontColor(this.state.pal.TEXT_SUB)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.alignItems(HorizontalAlign.Start).width('100%')
      }.layoutWeight(1).borderRadius(0).backgroundColor(Color.Transparent).hoverEffect(HoverEffect.Highlight)
        .accessibilityText(`打开 ${RecentFileList.displayName(item.documentId)}`)
        .padding({ top: 16, bottom: 16 }).onClick(() => this.actions.openRecent(item))
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.pin')).fontSize(16)
          .rotate({ angle: item.pinned ? -45 : 0 })
          .fontColor([item.pinned ? this.state.pal.PRIMARY : this.state.pal.TEXT_FAINT])
      }.attributeModifier(new ControlStyle(this.state.pal, 'quiet', true))
        .accessibilityText(`${item.pinned ? '取消置顶' : '置顶'} ${RecentFileList.displayName(item.documentId)}`)
        .accessibilitySelected(item.pinned)
        .onClick(() => this.actions.togglePin(item.documentId))
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.trash')).fontSize(16).fontColor([this.state.pal.TEXT_SUB])
      }.attributeModifier(new ControlStyle(this.state.pal, 'quiet', true))
        .accessibilityText(`删除 ${RecentFileList.displayName(item.documentId)}`)
        .onClick(() => this.actions.deleteRecent(item.documentId))
    }.width('100%').padding({ left: 14, right: 4 })
      .backgroundColor(this.state.pal.CONTENT).borderRadius(8).margin({ bottom: 8 })
  }
  @Builder
  phoneHome() {
    Column({ space: 10 }) {
      if (this.state.compactHeight && this.captionBottom > 0) { Blank().height(this.captionBottom) }
      if (!this.state.compactHeight) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text('木笺').fontSize(26).fontWeight(FontWeight.Medium).fontColor(this.state.pal.TEXT)
          Text('本机 Markdown 文档').fontSize(12).fontColor(this.state.pal.TEXT_SUB)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          .onTouch((event: TouchEvent) => { if (event.type === TouchType.Down) { beginWindowMove(this.actions.env.ctx); } })
        Button('新建', { type: ButtonType.Normal })
          .attributeModifier(new ControlStyle(this.state.pal, 'primary')).onClick(() => this.actions.goEditor())
      }.width('100%').padding({ top: 6, bottom: 14 })
      }

      Row({ space: 10 }) {
        Button('打开文档', { type: ButtonType.Normal })
          .layoutWeight(1)
          .attributeModifier(new ControlStyle(this.state.pal, 'secondary'))
          .onClick(() => this.actions.openExternalFile())
        Button('我的文档', { type: ButtonType.Normal })
          .layoutWeight(1)
          .attributeModifier(new ControlStyle(this.state.pal, 'secondary'))
          .onClick(() => this.actions.openLibraryFile())
      }
      .width('100%')

      if (!this.state.compactHeight && this.state.draftCount > 0) {
        this.navRow(`找回未保存内容（${this.state.draftCount}）`, () => this.actions.goRecovery())
      }

      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索文档内容', text: this.state.searchQuery })
          .fontSize(13)
          .height(ControlMetrics.HEIGHT)
          .padding({ left: 14, right: 12 })
          .backgroundColor(this.state.pal.CONTENT)
          .borderRadius(ControlMetrics.RADIUS)
          .border({ width: 1, color: this.state.pal.DIVIDER })
          .layoutWeight(1)
          .onChange((v: string) => {
            this.state.searchQuery = v;
            this.actions.scheduleSearch();
          })
        if (this.state.searchQuery.length > 0) {
          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(20).fontColor([this.state.pal.TEXT])
          }
            .attributeModifier(new ControlStyle(this.state.pal, 'quiet', true)).accessibilityText('关闭')
            .onClick(() => {
              this.state.searchQuery = '';
              this.state.searchResults = [];
            })
        }
      }
      .width('100%')

      if (this.state.pickingFile) {
        Scroll() { HomeLibraryPanel({ state: this.state, actions: this.actions }) }
          .width('100%').layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Auto)
      } else if (this.state.searchQuery.length > 0) {
        if (this.state.searchResults.length === 0 && !this.state.searchBusy) {
          Text('没有匹配的文档')
            .fontSize(13)
            .fontColor(this.state.pal.TEXT_FAINT)
            .padding({ top: 12 })
        }
        List({ space: 0 }) {
          ForEach(this.state.searchResults, (r: DocSearchResult) => {
            ListItem() {
              Button({ type: ButtonType.Normal }) {
              Column({ space: 3 }) {
                Text(r.name)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.state.pal.TEXT)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(r.snippet)
                  .fontSize(11)
                  .fontColor(this.state.pal.TEXT_FAINT)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${r.count} 处命中`)
                  .fontSize(11)
                  .fontColor(this.state.pal.PRIMARY)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ top: 11, bottom: 11, left: 4, right: 4 })
              .border({ width: { bottom: 1 }, color: this.state.pal.DIVIDER })
              }
              .width('100%').borderRadius(0).padding(0).backgroundColor(Color.Transparent)
              .hoverEffect(HoverEffect.Highlight).accessibilityText(`打开 ${r.name}`)
              .onClick(() => this.actions.goEditorWithResult(r.name))
            }
          }, (r: DocSearchResult) => `${r.name}-${r.count}`)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      } else {
        Row() {
          Text('最近')
            .fontSize(13)
            .fontColor(this.state.pal.TEXT_SUB)
          Blank()
          if (this.state.recent.length > 0) {
            Text(`${this.state.recent.length} 个文档`)
              .fontSize(12)
              .fontColor(this.state.pal.TEXT_FAINT)
          }
        }
        .width('100%')
        .padding({ top: 10, bottom: 2 })

        if (this.state.recent.length === 0) {
          Text('还没有最近文档').fontSize(16).fontColor(this.state.pal.TEXT).padding({ top: 28 })
          Text('新建一页，或打开已有的 Markdown 文档。').fontSize(13).fontColor(this.state.pal.TEXT_SUB)
        }
        List({ space: 0 }) {
          ForEach(this.state.recent, (item: RecentEntry) => {
            ListItem() {
              this.recentRow(item)
            }
          }, (item: RecentEntry) => `${item.documentId}-${item.pinned}`)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 20, right: 20, top: 16 })
    .alignItems(HorizontalAlign.Start)
  }
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
  build() { this.phoneHome() }
}
