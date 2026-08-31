import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';
import { RecentFileList, RecentEntry } from '../domain/document/RecentFileList';
import { MetadataStore } from '../infrastructure/metadata/MetadataStore';
import { InternalFileSource } from '../infrastructure/file/InternalFileSource';
import { DraftStore } from '../infrastructure/metadata/DraftStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-HOME';

/**
 * M5-01 正式首页：最近文件 + 固定文件 + 资料库入口 + 崩溃恢复入口（M4-04）。
 * 数据：MetadataStore（preferences）持久化最近列表；资料库文件由 InternalFileSource 枚举；
 * 恢复入口由 DraftStore 检查点数量驱动。
 */
@Entry
@Component
struct HomePage {
  @State recent: RecentEntry[] = [];
  @State libraryFiles: string[] = [];
  @State draftCount: number = 0;
  @State pickingFile: boolean = false;
  @State log: string = '';
  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private meta: MetadataStore = new MetadataStore(getContext(this) as common.UIAbilityContext);
  private fileSource: InternalFileSource = new InternalFileSource(getContext(this) as common.UIAbilityContext);
  private draftStore: DraftStore = new DraftStore(getContext(this) as common.UIAbilityContext);

  private append(line: string): void {
    this.log = `${line}\n---\n${this.log}`;
    hilog.info(DOMAIN, TAG, '%{public}s', line);
  }

  async aboutToAppear(): Promise<void> {
    await this.refresh();
    await this.refreshRecovery();
  }

  /** 页面每次显示（含从编辑器返回）时刷新最近列表与恢复入口 */
  onPageShow(): void {
    this.refresh();
    this.refreshRecovery();
  }

  /** M4-04 恢复入口：存在未处理检查点时提示（含损坏草稿的保守处理——整目录由用户决定） */
  private async refreshRecovery(): Promise<void> {
    try {
      this.draftCount = this.draftStore.listAll().length;
    } catch (e) {
      this.draftCount = 0;
    }
    if (this.draftCount > 0) {
      this.append(`[恢复] ${this.draftCount} 个检查点（保存/强杀后未落盘内容）`);
    }
  }

  private goRecovery(): void {
    router.pushUrl({ url: 'pages/RecoveryPage' });
  }

  private async refresh(): Promise<void> {
    const entries = await this.meta.loadRecent();
    this.recent = new RecentFileList(entries).snapshot();
    this.append(`[最近] ${this.recent.length} 条`);
  }

  private async refreshLibrary(): Promise<void> {
    try {
      const names = this.fileSource.listLibrary();
      this.libraryFiles = names;
      this.append(`[资料库] ${names.length} 个文档`);
    } catch (e) {
      this.append(`[资料库] 读取失败：${JSON.stringify(e)}`);
    }
  }

  private goEditor(): void {
    router.pushUrl({ url: 'pages/EditorPage' });
  }

  /** 打开最近/资料库文档（M5-01：name 参数 → EditorPage 读取并加载） */
  private goEditorWith(name: string): void {
    const params: ESObject = { name: name } as ESObject;
    router.pushUrl({ url: 'pages/EditorPage', params: params });
  }

  /** M5-01「打开文件」正式入口：枚举资料库选择（无外部 picker 依赖，V0.1 内部库） */
  private openLibraryFile(): void {
    this.refreshLibrary().then(() => {
      this.pickingFile = true;
    });
  }

  build() {
    Column({ space: 8 }) {
      Text('Markdown Workbench')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
      Button('新建文档')
        .fontSize(13)
        .onClick(() => this.goEditor())
      Button('打开文件')
        .fontSize(13)
        .onClick(() => this.openLibraryFile())
      Button('刷新')
        .fontSize(13)
        .onClick(() => this.refresh())
      Button('设置')
        .fontSize(13)
        .onClick(() => { router.pushUrl({ url: 'pages/SettingsPage' }); })
    }
    .width('100%')

      Text('最近文件')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)

      // M5-01 打开文件：资料库文件选择（内联列表，空态提示）
      if (this.pickingFile) {
        Column({ space: 4 }) {
          Text('选择资料库文档')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
          if (this.libraryFiles.length === 0) {
            Text('资料库为空。新建文档保存后，正文会存入应用私有目录（本机离线可用）。')
              .fontSize(12)
              .fontColor('#99000000')
          }
          Scroll() {
            Column({ space: 2 }) {
              ForEach(this.libraryFiles, (name: string) => {
                Text(`📄 ${name}`)
                  .fontSize(13)
                  .width('100%')
                  .padding(4)
                  .onClick(() => {
                    this.pickingFile = false;
                    this.goEditorWith(name);
                  })
              }, (name: string) => name)
            }
            .width('100%')
          }
          .height(150)
          .width('100%')
          Button('取消')
            .fontSize(12)
            .onClick(() => { this.pickingFile = false; })
        }
        .width('100%')
        .padding(8)
        .backgroundColor('#F5F5F5')
        .borderRadius(6)
      }

      if (this.draftCount > 0) {
        Button(`找回未保存内容（${this.draftCount}）`)
          .fontSize(13)
          .backgroundColor('#B26A00')
          .onClick(() => this.goRecovery())
      }

      List({ space: 4 }) {
        ForEach(this.recent, (item: RecentEntry) => {
          ListItem() {
            Row({ space: 8 }) {
              Text(item.pinned ? '📌' : '•')
                .fontSize(13)
              Text(item.documentId)
                .fontSize(13)
              Text(new Date(item.lastOpenedAt).toLocaleString('zh-CN'))
                .fontSize(10)
                .fontColor('#99000000')
            }
            .width('100%')
            .onClick(() => this.goEditorWith(item.documentId))
          }
        }, (item: RecentEntry) => item.documentId)
      }
      .height(160)
      .width('100%')

      Text(`资料库：${this.libraryFiles.length} 个文档`)
        .fontSize(12)
        .fontColor('#99000000')

      Divider()

      Text('开发入口（M0-M3 尖峰页）')
        .fontSize(12)
        .fontColor('#666666')

      Flex({ wrap: FlexWrap.Wrap }) {
        Button('URI').fontSize(11).onClick(() => { router.pushUrl({ url: 'pages/SpikeUriPage' }); })
        Button('保存').fontSize(11).onClick(() => { router.pushUrl({ url: 'pages/SpikeSavePage' }); })
        Button('元数据').fontSize(11).onClick(() => { router.pushUrl({ url: 'pages/SpikeMetadataPage' }); })
        Button('资料库').fontSize(11).onClick(() => { router.pushUrl({ url: 'pages/SpikeLibraryPage' }); })
        Button('预览').fontSize(11).onClick(() => { router.pushUrl({ url: 'pages/SpikePreviewPage' }); })
        Button('编辑器').fontSize(11).onClick(() => { router.pushUrl({ url: 'pages/SpikeEditorPage' }); })
        Button('契约').fontSize(11).onClick(() => { router.pushUrl({ url: 'pages/SpikeContractPage' }); })
        Button('库刷新').fontSize(11).onClick(() => this.refreshLibrary())
      }
      .width('100%')

      Text(this.log)
        .fontSize(10)
        .fontColor('#99000000')
        .maxLines(3)
        .width('100%')
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }
}