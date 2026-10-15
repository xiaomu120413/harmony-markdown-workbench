import { RecentFileList, RecentEntry } from '../domain/document/RecentFileList';
import { AppTheme } from '../common/AppTheme';

/**
 * 文档侧栏（B1/B2：编辑页内切换文档，不必返回首页）。
 * 最近 + 固定 + 资料库三段列表，共用搜索。
 * 选择文档经回调（调用方负责 A3 离开流程与加载）。
 */
@Component
export struct DocumentSidebar {
  @Link recent: RecentEntry[];
  @Link libraryFiles: string[];
  @Prop pal: AppTheme = AppTheme.light();
  @State filter: 'recent' | 'pinned' | 'library' = 'recent';
  @State searchQuery: string = '';
  private onDocSelected: (docId: string) => void = () => {};

  private fmtTime(ms: number): string {
    const d = new Date(ms);
    const hh = `${d.getHours()}`.padStart(2, '0');
    const mm = `${d.getMinutes()}`.padStart(2, '0');
    return `${d.getMonth() + 1}/${d.getDate()} ${hh}:${mm}`;
  }

  private get pinned(): RecentEntry[] {
    return this.recent.filter((e: RecentEntry): boolean => e.pinned);
  }

  private get visibleRecent(): RecentEntry[] {
    if (this.filter === 'pinned') {
      return this.pinned;
    }
    return this.recent;
  }

  private get visibleLibrary(): string[] {
    if (this.searchQuery.trim().length > 0) {
      const q = this.searchQuery.trim().toLowerCase();
      return this.libraryFiles.filter((n: string): boolean => n.toLowerCase().includes(q));
    }
    return this.libraryFiles;
  }

  @Builder
  filterTab(label: string, mode: 'recent' | 'pinned' | 'library', count: number) {
    Text(mode === this.filter ? `${label} ${count}` : label)
      .fontSize(12)
      .fontWeight(this.filter === mode ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.filter === mode ? this.pal.PRIMARY : this.pal.TEXT_SUB)
      .padding({ left: 8, right: 8, top: 5, bottom: 5 })
      .borderRadius(6)
      .backgroundColor(this.filter === mode ? this.pal.PRIMARY_SOFT : Color.Transparent)
      .onClick(() => {
        this.filter = mode;
      })
  }

  @Builder
  docRow(name: string, sub: string, docId: string) {
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
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 8, bottom: 8, left: 12, right: 8 })
    .borderRadius(8)
    .onClick(() => this.onDocSelected(docId))
  }

  build() {
    Column({ space: 0 }) {
      // 筛选 Tab
      Row({ space: 4 }) {
        this.filterTab('最近', 'recent', this.recent.length)
        this.filterTab('固定', 'pinned', this.pinned.length)
        this.filterTab('资料库', 'library', this.libraryFiles.length)
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 6, bottom: 4 })

      // 搜索框
      TextInput({ placeholder: '搜索文档', text: this.searchQuery })
        .fontSize(12)
        .height(32)
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
      List({ space: 0 }) {
        if (this.filter === 'library') {
          ForEach(this.visibleLibrary, (name: string) => {
            ListItem() {
              this.docRow(name, '资料库', `library/${name}`)
            }
          }, (name: string) => name)
        } else {
          ForEach(this.visibleRecent, (item: RecentEntry) => {
            ListItem() {
              this.docRow(
                RecentFileList.displayName(item.documentId),
                this.fmtTime(item.lastOpenedAt),
                item.documentId,
              )
            }
          }, (item: RecentEntry) => `${item.documentId}-${this.filter}`)
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
