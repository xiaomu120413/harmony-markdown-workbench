import { ControlStyle, ControlMetrics } from '../../common/ControlStyle';
import { RecentFileList, RecentEntry } from '../../domain/document/RecentFileList';
import { DocSearchResult } from '../../domain/document/LibrarySearch';
import { HomeState } from './HomeState';
import { HomeController } from './HomeController';

@Component
export struct HomeRecentList {
  @StorageProp('titleControlsWidth') captionWidth: number = 0;
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
          .fontSize(11).fontColor(this.state.pal.TEXT_FAINT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.alignItems(HorizontalAlign.Start).width('100%')
      }.layoutWeight(1).borderRadius(0).backgroundColor(Color.Transparent).hoverEffect(HoverEffect.Highlight)
        .accessibilityText(`打开 ${RecentFileList.displayName(item.documentId)}`)
        .padding({ top: 10, bottom: 10 }).onClick(() => this.actions.openRecent(item))
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
    }.width('100%').padding({ left: 12, right: 4 })
  }
  @Builder
  recentColumn() {
    Column({ space: 0 }) {
      Row() {
        Text(this.state.searchQuery.length > 0 ? '搜索结果' : '最近')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.state.pal.TEXT)
          .layoutWeight(1)
        if (this.state.searchQuery.length > 0) {
          Text(this.state.searchBusy ? '搜索中…' : `${this.state.searchResults.length} 篇`)
            .fontSize(12)
            .fontColor(this.state.pal.TEXT_FAINT)
        } else if (this.state.recent.length > 0) {
          Text(`${this.state.recent.length} 个文档`)
            .fontSize(12)
            .fontColor(this.state.pal.TEXT_FAINT)
        }
      }
      .width('100%')
      .height(52)
      .padding({ left: 20, right: 16 + (this.state.bp === 'tablet' ? this.captionWidth : 0) })

      // 资料库全文搜索框（V0.4.3）
      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索文档内容', text: this.state.searchQuery })
          .fontSize(13)
          .height(ControlMetrics.HEIGHT)
          .padding({ left: 0, right: 8 })
          .backgroundColor(Color.Transparent)
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
      .padding({ left: 20, right: 16, bottom: 6 })

      if (this.state.searchQuery.length > 0) {
        // 搜索结果列表
        if (this.state.searchResults.length === 0 && !this.state.searchBusy) {
          Text('没有匹配的文档')
            .fontSize(13)
            .fontColor(this.state.pal.TEXT_FAINT)
            .padding({ top: 16, left: 20 })
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
              .padding({ top: 11, bottom: 11, left: 20, right: 16 })
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
        if (this.state.recent.length === 0) {
          Text('打开过的文档会出现在这里')
            .fontSize(13)
            .fontColor(this.state.pal.TEXT_FAINT)
            .padding({ top: 16, left: 20 })
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
    .width(this.state.bp === 'pc' ? 300 : '100%')
    .layoutWeight(this.state.bp === 'tablet' ? 1 : 0)
    .height('100%')
    .backgroundColor(this.state.pal.BG)
    .alignItems(HorizontalAlign.Start)
  }
  build() { this.recentColumn() }
}
