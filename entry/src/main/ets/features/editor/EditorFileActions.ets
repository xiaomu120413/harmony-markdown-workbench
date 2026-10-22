import { ControlStyle, ControlMetrics } from '../../common/ControlStyle';
import { EditorState } from './EditorState';
import { EditorController } from './EditorController';
import { OutlineEntry } from './EditorState';

@Component
export struct EditorFileActions {
  @ObjectLink state: EditorState;
  @Require actions: EditorController;
  @Builder
  fileMenu() {
    Menu() {
      MenuItemGroup() {
        MenuItem({ content: '新建文档' }).onClick(() => this.actions.newDocument())
        MenuItem({ content: '打开文档…' }).onClick(() => this.actions.openDocument())
        MenuItem({ content: '另存为…' }).onClick(() => this.actions.deliverDocument(0))
      }
      MenuItemGroup() {
        MenuItem({ content: '导出副本', builder: this.exportMenu })
        MenuItem({ content: '复制内容', builder: this.copyMenu })
        MenuItem({ content: '查看保存位置' }).onClick(() => this.actions.showLocation())
      }
      if (this.state.docTarget?.kind === 'internal') {
        MenuItemGroup() {
          MenuItem({ content: '删除文档' }).contentFontColor(this.state.pal.DANGER).onClick(() => this.actions.deleteCurrentDocument())
        }
      }
    }.width(264)
  }
  @Builder
  exportMenu() {
    Menu() {
      MenuItem({ content: '图文包 ZIP', labelInfo: '正文和图片' }).onClick(() => this.actions.deliverDocument(2))
      MenuItem({ content: '网页 HTML', labelInfo: '内嵌图片' }).onClick(() => this.actions.deliverDocument(3))
      MenuItem({ content: 'Markdown', labelInfo: '仅正文' }).onClick(() => this.actions.deliverDocument(1))
    }
  }
  @Builder
  fileActionRow(label: string, detail: string, next: boolean, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text(label).fontSize(ControlMetrics.FONT).fontColor(this.state.pal.TEXT).maxLines(1)
          if (detail.length > 0) {
            Text(detail).fontSize(12).fontColor(this.state.pal.TEXT_SUB).maxLines(2)
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (next) { SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([this.state.pal.TEXT_SUB]) }
      }.width('100%')
    }
    .width('100%').constraintSize({ minHeight: 56 }).padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(Color.Transparent).borderRadius(ControlMetrics.RADIUS).hoverEffect(HoverEffect.Highlight)
    .accessibilityText(`${label}，${detail}`).onClick(action)
  }
  @Builder
  fileSheet() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        if (this.state.fileSheetSection !== 'root') {
          Button('返回', { type: ButtonType.Normal })
            .attributeModifier(new ControlStyle(this.state.pal, 'quiet')).onClick(() => { this.state.fileSheetSection = 'root'; })
        }
        Text(this.state.fileSheetSection === 'root' ? '文档操作' : this.state.fileSheetSection === 'export' ? '导出副本' : this.state.fileSheetSection === 'outline' ? '文档大纲' : '复制内容')
          .fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.state.pal.TEXT).layoutWeight(1)
        Button('关闭', { type: ButtonType.Normal })
          .attributeModifier(new ControlStyle(this.state.pal, 'quiet')).onClick(() => { this.state.fileSheetVisible = false; })
      }.width('100%')
      Column({ space: 4 }) {
        Text(this.state.docTitle).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.state.pal.TEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.actions.documentLocation()} · ${this.state.saveLabel}`).fontSize(12).fontColor(this.state.pal.TEXT_SUB).maxLines(2)
      }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: 12, right: 12, bottom: 8 })
      Divider().color(this.state.pal.DIVIDER)
      Scroll() {
        Column({ space: 2 }) {
          if (this.state.fileSheetSection === 'root') {
            this.fileActionRow('新建文档', '', false, () => this.actions.dismissFileSheet(() => this.actions.newDocument()))
            this.fileActionRow('打开文档', '选择要继续编辑的原文件', false, () => this.actions.dismissFileSheet(() => this.actions.openDocument()))
            this.fileActionRow('另存为', '保存后继续编辑新文件', false, () => this.actions.dismissFileSheet(() => this.actions.deliverDocument(0)))
            Divider().color(this.state.pal.DIVIDER).margin({ top: 4, bottom: 4 })
            this.fileActionRow('导出副本', '选择格式，保留当前保存位置', true, () => { this.state.fileSheetSection = 'export'; })
            this.fileActionRow('复制内容', '', true, () => { this.state.fileSheetSection = 'copy'; })
            this.fileActionRow('保存位置', this.actions.documentLocation(), false, () => this.actions.dismissFileSheet(() => this.actions.showLocation()))
            this.fileActionRow('设置与使用帮助', '', false, () => this.actions.dismissFileSheet(() => this.actions.showSettings()))
            if (this.state.docTarget?.kind === 'internal') {
              Divider().color(this.state.pal.DIVIDER).margin({ top: 4, bottom: 4 })
              this.fileActionRow('删除文档', '直接删除，无法恢复', false,
                () => this.actions.dismissFileSheet(() => this.actions.deleteCurrentDocument()))
            }
          } else if (this.state.fileSheetSection === 'export') {
            this.fileActionRow('图文包 ZIP', 'Markdown 正文和引用的本地图片', false, () => this.actions.dismissFileSheet(() => this.actions.deliverDocument(2)))
            this.fileActionRow('网页 HTML', '在浏览器查看，本地图片嵌入文件', false, () => this.actions.dismissFileSheet(() => this.actions.deliverDocument(3)))
            this.fileActionRow('Markdown', '仅保存正文，不包含图片附件', false, () => this.actions.dismissFileSheet(() => this.actions.deliverDocument(1)))
          } else if (this.state.fileSheetSection === 'outline') {
            if (this.state.outlineEntries.length === 0) {
              Text('添加 Markdown 标题后，可在这里快速跳转。').fontSize(14).fontColor(this.state.pal.TEXT_SUB).padding(12)
            }
            ForEach(this.state.outlineEntries, (entry: OutlineEntry) => {
              this.fileActionRow(`${'#'.repeat(entry.level)} ${entry.text}`, '', false,
                () => this.actions.dismissFileSheet(() => this.actions.jumpToOutlineEntry(entry)))
            })
          } else {
            this.fileActionRow('Markdown 原文', '', false, () => this.actions.dismissFileSheet(() => this.actions.deliverDocument(4)))
            this.fileActionRow('渲染 HTML', '', false, () => this.actions.dismissFileSheet(() => this.actions.deliverDocument(7)))
          }
        }.width('100%')
      }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Auto)
    }.width('100%').height('100%').padding({ left: 16, right: 16, bottom: 24 })
      .backgroundColor(this.state.pal.CONTENT)
  }
  @Builder
  fileEntry() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 7 }) {
        SymbolGlyph(this.state.bp === 'phone' ? $r('sys.symbol.ellipsis_circle') : $r('sys.symbol.folder'))
          .fontSize(this.state.bp === 'phone' ? 22 : 18).fontColor([this.state.pal.TEXT])
        if (this.state.bp !== 'phone') {
          Text('文档').fontSize(14).fontColor(this.state.pal.TEXT)
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(11).fontColor([this.state.pal.TEXT_SUB])
        }
      }
    }
      .attributeModifier(new ControlStyle(this.state.pal,
      this.state.fileMenuVisible || this.state.fileSheetVisible ? 'selected' : 'quiet', this.state.bp === 'phone'))
    .accessibilityText('文档操作').id('document-actions')
    .enabled(!this.state.deliveryBusy && !this.state.dropBusy)
    .onClick(() => {
      if (this.state.bp === 'phone') { this.state.fileSheetSection = 'root'; this.state.fileSheetVisible = true; }
      else { this.state.fileMenuVisible = true; }
    })
    .bindMenu(this.state.bp !== 'phone' && this.state.fileMenuVisible, this.fileMenu, {
      showInSubWindow: false, onDisappear: () => { this.state.fileMenuVisible = false; },
    })
    .bindSheet(this.state.bp === 'phone' && this.state.fileSheetVisible, this.fileSheet, {
      height: '75%', preferType: SheetType.BOTTOM, showClose: false, dragBar: true,
      backgroundColor: this.state.pal.CONTENT, onDisappear: () => this.actions.fileSheetClosed(),
    })
  }
  @Builder
  copyMenu() {
    Menu() {
      MenuItem({ content: 'Markdown 原文' }).onClick(() => this.actions.deliverDocument(4))
      MenuItem({ content: '渲染 HTML' }).onClick(() => this.actions.deliverDocument(7))
    }
  }
  build() { this.fileEntry() }
}
