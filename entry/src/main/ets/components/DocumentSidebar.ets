import { RecentFileList, RecentEntry } from '../domain/document/RecentFileList';
import { AppTheme } from '../common/AppTheme';
import { ControlStyle, ControlMetrics } from '../common/ControlStyle';

/**
 * 文档侧栏（B1/B2：编辑页内切换文档，不必返回首页）。
 * 最近、置顶与资料库共用搜索，文件操作由调用方处理。
 * 选择文档经回调（调用方负责 A3 离开流程与加载）。
 */
@Component
export struct DocumentSidebar {
  @Prop recent: RecentEntry[] = [];
  @Prop libraryFiles: string[] = [];
  @Prop pal: AppTheme = AppTheme.light();
  @Prop busy: boolean = false;
  @State filter: 'recent' | 'pinned' | 'library' = 'recent';
  @State searchQuery: string = '';
  onDocSelected: (docId: string) => void = () => {};
  onDelete: (docId: string) => void = () => {};
  onPin: (docId: string) => void = () => {};

  private pinned(): RecentEntry[] {
    return this.recent.filter((e: RecentEntry): boolean => e.pinned);
  }

  private visibleRecent(): RecentEntry[] {
    const entries = this.filter === 'pinned' ? this.pinned() : this.recent;
    const q = this.searchQuery.trim().toLowerCase();
    return q.length === 0 ? entries : entries.filter((e: RecentEntry): boolean =>
      RecentFileList.displayName(e.documentId).toLowerCase().includes(q) || RecentFileList.location(e.documentId).toLowerCase().includes(q));
  }

  private visibleLibrary(): string[] {
    if (this.searchQuery.trim().length > 0) {
      const q = this.searchQuery.trim().toLowerCase();
      return this.libraryFiles.filter((n: string): boolean => n.toLowerCase().includes(q));
    }
    return this.libraryFiles;
  }

  @Builder
  filterTab(label: string, mode: 'recent' | 'pinned' | 'library', count: number) {
    Button(label, { type: ButtonType.Normal })
      .attributeModifier(new ControlStyle(this.pal, this.filter === mode ? 'selected' : 'quiet'))
      .accessibilityText(`${label}，${count} 个文档`).accessibilitySelected(this.filter === mode)
      .onClick(() => {
        this.filter = mode;
      })
  }

  @Builder
  docRow(name: string, sub: string, docId: string, pinned: boolean = false) {
    Row({ space: 0 }) {
      Column({ space: 2 }) {
        Text(name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(sub)
          .fontSize(10)
          .fontColor(this.pal.TEXT_FAINT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ top: 10, bottom: 10, left: 8 })
      .onClick(() => this.onDocSelected(docId))
      if (this.filter !== 'library') {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.pin')).fontSize(16)
            .rotate({ angle: pinned ? -45 : 0 })
            .fontColor([pinned ? this.pal.PRIMARY : this.pal.TEXT_FAINT])
        }.attributeModifier(new ControlStyle(this.pal, 'quiet', true)).enabled(!this.busy)
          .accessibilityText(`${pinned ? '取消置顶' : '置顶'} ${name}`)
          .accessibilitySelected(pinned)
          .onClick(() => this.onPin(docId))
      }
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.trash')).fontSize(16).fontColor([this.pal.TEXT_SUB])
      }.attributeModifier(new ControlStyle(this.pal, 'quiet', true)).enabled(!this.busy)
        .accessibilityText(`删除 ${name}`).onClick(() => this.onDelete(docId))
    }.width('100%')
  }

  build() {
    Column({ space: 0 }) {
      // 筛选 Tab
      Row({ space: 4 }) {
        this.filterTab('最近', 'recent', this.recent.length)
        this.filterTab('置顶', 'pinned', this.pinned().length)
        this.filterTab('资料库', 'library', this.libraryFiles.length)
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 6, bottom: 4 })

      // 搜索框
      TextInput({ placeholder: '搜索文档', text: this.searchQuery })
        .fontSize(12)
        .height(ControlMetrics.HEIGHT)
        .padding({ left: 10, right: 8 })
        .backgroundColor(this.pal.CARD)
        .borderRadius(8)
        .width('100%')
        .margin({ left: 8, right: 8 })
        .constraintSize({ maxWidth: '92%' })
        .onChange((v: string) => {
          this.searchQuery = v;
        })

      // 列表
      if (this.searchQuery.trim().length > 0 &&
        (this.filter === 'library' ? this.visibleLibrary().length === 0 : this.visibleRecent().length === 0)) {
        Text('没有匹配的文档').fontSize(12).fontColor(this.pal.TEXT_FAINT).padding(12)
      } else if (this.filter === 'pinned' && this.pinned().length === 0) {
        Text('点击文档旁的图钉，将常用文档置顶')
          .fontSize(12).fontColor(this.pal.TEXT_FAINT).padding(12)
      }
      List({ space: 0 }) {
        if (this.filter === 'library') {
          ForEach(this.visibleLibrary(), (name: string) => {
            ListItem() {
              this.docRow(name, '资料库', `library/${name}`)
            }
          }, (name: string) => name)
        } else {
          ForEach(this.visibleRecent(), (item: RecentEntry) => {
            ListItem() {
              this.docRow(
                RecentFileList.displayName(item.documentId),
                RecentFileList.location(item.documentId),
                item.documentId,
                item.pinned,
              )
            }
          }, (item: RecentEntry) => `${item.documentId}-${this.filter}-${item.pinned}`)
        }
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .margin({ top: 4 })
    }
    .width(240)
    .height('100%')
    .padding({ left: 6, right: 6, top: 4, bottom: 6 })
    .backgroundColor(this.pal.SIDEBAR)
    .alignItems(HorizontalAlign.Start)
  }
}
