import { MuLogger } from '../../common/MuLogger';
import { ControlStyle } from '../../common/ControlStyle';
import { WebDragStyle } from '../../common/WebDragStyle';
import { router } from '@kit.ArkUI';
import { DocumentSidebar } from '../../components/DocumentSidebar';
import { DefaultView } from '../../domain/settings/AppSettings';
import { EditorState } from './EditorState';
import { EditorController } from './EditorController';
import { OutlineEntry } from './EditorState';

@Component
export struct EditorWorkspace {
  @ObjectLink state: EditorState;
  @Require actions: EditorController;
  build() {
      // A2 恢复面板：外部文档读取失败/授权失效（不呈现可正常保存的空白文档）
      if (this.state.loadState === 'loadFailed' || this.state.loadState === 'accessExpired') {
        Column({ space: 12 }) {
          Text(this.state.loadState === 'accessExpired' ? '无法访问文件' : '文件读取失败')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.state.pal.TEXT)
          Text(this.state.loadState === 'accessExpired'
            ? '外部文件的访问授权已失效（重启或授权过期）。可重新选择文件，或将内容另存到资料库。'
            : '文件可能已被移动、删除或暂时不可读。可将编辑器中的内容另存到资料库，或返回后再试。')
            .fontSize(13)
            .fontColor(this.state.pal.TEXT_SUB)
            .lineHeight(20)
          Text(this.state.loadFailure).fontSize(12).fontColor(this.state.pal.DANGER).maxLines(3)
          Flex({ wrap: FlexWrap.Wrap }) {
            if (this.state.docTarget !== undefined && this.state.docTarget.kind === 'external') {
              Button('重新选择文件', { type: ButtonType.Normal })
                .attributeModifier(new ControlStyle(this.state.pal, 'primary'))
                .onClick(() => this.actions.reselectExternalFile())
            }
            Button('查看恢复草稿', { type: ButtonType.Normal })
              .attributeModifier(new ControlStyle(this.state.pal, 'quiet'))
              .onClick(() => router.pushUrl({ url: 'pages/RecoveryPage' }))
            Button('返回', { type: ButtonType.Normal })
              .attributeModifier(new ControlStyle(this.state.pal, 'quiet'))
              .onClick(() => router.back())
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding(28)
      } else {
      // 工作区：大纲（可选）+ 编辑器 + 预览（三端同一布局路径——
      // phone：单栏互斥切换；tablet/pc 分屏：双 Web 并排；隐藏侧 Visibility.None 不占位）
      Stack() {
      Row({ space: 0 }) {
        // B1/B2：文档侧栏（编辑页内切换文档，phone 档可折叠）
        if (this.state.sidebarVisible && this.state.bp !== 'phone') {
          DocumentSidebar({
            recent: this.state.sidebarRecent,
            libraryFiles: this.state.sidebarLibrary,
            pal: this.state.pal,
            busy: this.state.deliveryBusy,
            onDelete: (docId: string) => this.actions.deleteDocument(docId),
            onPin: (docId: string) => this.actions.toggleRecentPin(docId),
            onDocSelected: (docId: string): void => {
              this.actions.switchToDocument(docId);
            },
          })
          Divider().vertical(true).height('100%').color(this.state.pal.DIVIDER)
        }

        // 大纲侧栏（FR-PREVIEW-003 总装：点击跳转标题行）
        if (this.state.outlineVisible && this.state.bp !== 'phone') {
          Column() {
            Text('大纲')
              .fontSize(12)
              .fontColor(this.state.pal.TEXT_SUB)
              .padding({ left: 8, top: 8, bottom: 4 })
              .width('100%')
            if (this.state.outlineEntries.length === 0) {
              Text('暂无标题（用 H1–H3 或输入 # 添加）')
                .fontSize(12)
                .fontColor(this.state.pal.TEXT_FAINT)
                .padding(8)
            }
            List() {
              ForEach(this.state.outlineEntries, (e: OutlineEntry) => {
                ListItem() {
                  Text(e.text)
                    .fontSize(13)
                    .fontColor(e.level === 1 ? this.state.pal.TEXT : this.state.pal.TEXT_SUB)
                    .fontWeight(e.level === 1 ? FontWeight.Medium : FontWeight.Normal)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .padding({ left: 8 + (e.level - 1) * 12, top: 6, bottom: 6, right: 8 })
                    .width('100%')
                    .onClick(() => this.actions.jumpToOutlineEntry(e))
                }
              }, (e: OutlineEntry) => `${e.from}-${e.text}`)
            }
            .layoutWeight(1)
            .width('100%')
            .scrollBar(BarState.Auto)
          }
          .width(200)
          .height('100%')
          .backgroundColor(this.state.pal.SIDEBAR)
          .clip(true)
        }

        if (this.state.outlineVisible) {
          Divider().vertical(true).height('100%').color(this.state.pal.DIVIDER)
        }

        Column() {
          Web({ src: $rawfile('web/editor.html'), controller: this.actions.env.controller })
            .javaScriptAccess(true)
            .attributeModifier(new WebDragStyle())
            .onDragEnter(() => { this.state.fileHover = true; })
            .onOverrideUrlLoading((request: WebResourceRequest): boolean => {
              return !request.getRequestUrl().endsWith('/web/editor.html');
            })
            .javaScriptProxy({
              object: { send: (raw: string): void => { this.actions.sendBridge(raw); } },
              name: '__nativeBridge',
              methodList: ['send'],
              controller: this.actions.env.controller,
            })
            .onPageEnd(() => {
              this.actions.env.webReady = true;
              // 补发样式：aboutToAppear 时 Web 可能未就绪，样式命令会被吞掉
              this.actions.applyEditorStyle();
              if (this.state.loadState === 'ready') {
                this.actions.flushPendingLoad();
              }
              MuLogger.info('编辑器就绪');
            })
            .onContextMenuShow((_event: OnContextMenuShowEvent): boolean => {
              return false; // 使用 ArkWeb 默认菜单（剪切/复制/粘贴/全选）
            })
            .onErrorReceive((event) => {
              MuLogger.info(`页面错误：${JSON.stringify(event.request)}`);
            })
            .layoutWeight(1)
            .width('100%')
        }
        .visibility(this.state.viewMode === DefaultView.PREVIEW ? Visibility.None : Visibility.Visible)
        .layoutWeight(1)
        .height('100%')
        .width('100%')
        .backgroundColor(this.state.pal.CONTENT)
        .clip(true)

        if (this.state.viewMode === DefaultView.SPLIT) {
          Divider()
            .vertical(true)
            .height('92%')
            .color(this.state.pal.DIVIDER)
        }

        Column() {
          Web({ src: $rawfile('web/preview.html'), controller: this.actions.env.previewController })
            .javaScriptAccess(true)
            .attributeModifier(new WebDragStyle())
            .onDragEnter(() => { this.state.fileHover = true; })
            .onOverrideUrlLoading((request: WebResourceRequest): boolean => {
              if (!request.isMainFrame() && request.getRequestUrl().startsWith('data:text/html;base64,')) { return false; }
              return !request.getRequestUrl().endsWith('/web/preview.html');
            })
            .onPageEnd(() => {
              this.actions.env.previewEpoch++;
              this.actions.env.previewReady = true;
              this.actions.applyPreviewStyle();
              this.actions.syncDocNow();
              MuLogger.info('预览就绪');
            })
            .onContextMenuShow((_event: OnContextMenuShowEvent): boolean => {
              return false; // 预览同样允许默认复制菜单
            })
            .onErrorReceive((event) => {
              MuLogger.info(`预览页面错误：${JSON.stringify(event.request)}`);
            })
            .layoutWeight(1)
            .width('100%')
        }
        .visibility(this.state.viewMode === DefaultView.EDIT ? Visibility.None : Visibility.Visible)
        .layoutWeight(1)
        .height('100%')
        .width('100%')
        .clip(true)
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .height('100%')
      if (this.state.fileHover) {
        Column({ space: 10 }) {
          Text('松开以打开文档或插入 HTML').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.state.pal.PRIMARY)
          Text('HTML 插入当前光标 · Markdown / txt 导入副本').fontSize(14).fontColor(this.state.pal.TEXT_SUB)
        }
        .justifyContent(FlexAlign.Center)
        .width('100%').height('100%').backgroundColor(this.state.pal.PRIMARY_SOFT)
        .onDrop((event: DragEvent) => { this.actions.receiveDrop(event); }, { disableDataPrefetch: true })
        .onDragLeave(() => { this.state.fileHover = false; })
      }
      }
      .layoutWeight(1).width('100%').height('100%')
      }

  }
}
