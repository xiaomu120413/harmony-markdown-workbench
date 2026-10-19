import { ControlStyle, ControlMetrics } from '../../common/ControlStyle';
import { MarkdownCommandName } from '../../domain/editor/MarkdownCommands';
import { SegBtn } from '../../common/SegBtn';
import { DefaultView } from '../../domain/settings/AppSettings';
import { EditorState } from './EditorState';
import { EditorController } from './EditorController';

@Component
export struct EditorCommandBar {
  @ObjectLink state: EditorState;
  @Require actions: EditorController;
  @Builder
  viewControls() {
    SegBtn({ label: '编辑', active: this.state.viewMode === DefaultView.EDIT, pal: this.state.pal, action: () => this.actions.setViewMode(DefaultView.EDIT) })
    SegBtn({ label: '预览', active: this.state.viewMode === DefaultView.PREVIEW, pal: this.state.pal, action: () => this.actions.setViewMode(DefaultView.PREVIEW) })
    SegBtn({ label: '分屏', active: this.state.viewMode === DefaultView.SPLIT, pal: this.state.pal, action: () => this.actions.setViewMode(DefaultView.SPLIT) })
  }
  @Builder
  navigationTools() {
    Button('查找', { type: ButtonType.Normal })
      .attributeModifier(new ControlStyle(this.state.pal, this.state.findVisible ? 'selected' : 'quiet'))
      .onClick(() => { if (this.state.findVisible) { this.state.findVisible = false; } else { this.actions.openFind(); } })
    Button('大纲', { type: ButtonType.Normal })
      .attributeModifier(new ControlStyle(this.state.pal, this.state.outlineVisible ? 'selected' : 'quiet'))
      .onClick(() => this.actions.toggleOutline())
    Button('设置', { type: ButtonType.Normal })
      .attributeModifier(new ControlStyle(this.state.pal)).onClick(() => this.actions.showSettings())
  }
  @Builder
  commandItem(label: string, cmd: MarkdownCommandName) {
    MenuItem({ content: label }).onClick(() => this.actions.applyCommand(cmd))
  }
  @Builder
  commandMenu(kind: string) {
    Menu() {
      if (kind === '标题') {
        this.commandItem('一级标题 H1', 'h1')
        this.commandItem('二级标题 H2', 'h2')
        this.commandItem('三级标题 H3', 'h3')
        this.commandItem('四级标题 H4', 'h4')
        this.commandItem('五级标题 H5', 'h5')
        this.commandItem('六级标题 H6', 'h6')
      } else if (kind === '格式') {
        this.commandItem('加粗  Ctrl+B', 'bold')
        this.commandItem('斜体  Ctrl+I', 'italic')
        this.commandItem('删除线', 'strike')
        this.commandItem('行内代码', 'inlineCode')
        this.commandItem('高亮', 'highlight')
      } else if (kind === '段落') {
        MenuItemGroup({ header: '列表' }) {
          this.commandItem('无序列表', 'ul')
          this.commandItem('有序列表', 'ol')
          this.commandItem('任务列表', 'task')
        }
        MenuItemGroup({ header: '块与缩进' }) {
          this.commandItem('引用', 'quote')
          this.commandItem('代码块', 'codeBlock')
          this.commandItem('增加缩进', 'indent')
          this.commandItem('减少缩进', 'outdent')
        }
      } else {
        this.commandItem('链接', 'link')
        MenuItem({ content: '本地图片…' }).onClick(() => this.actions.insertLocalImage())
        this.commandItem('表格', 'table')
        this.commandItem('分隔线', 'hr')
      }
    }.width(220)
  }
  @Builder
  toolGroup(label: string) {
    Button(label, { type: ButtonType.Normal })
      .enabled(!this.state.deliveryBusy)
      .attributeModifier(new ControlStyle(this.state.pal, this.state.activeToolMenu === label ? 'selected' : 'quiet'))
      .onClick(() => { this.state.activeToolMenu = label; })
      .bindMenu(this.state.activeToolMenu === label, this.activeCommandMenu, {
        showInSubWindow: false, onDisappear: () => { this.state.activeToolMenu = ''; },
      })
  }
  @Builder
  activeCommandMenu() { this.commandMenu(this.state.activeToolMenu) }
  @Builder
  toolSep() {
    Divider()
      .vertical(true)
      .height(20)
      .color(this.state.pal.DIVIDER)
      .margin({ left: 5, right: 5 })
  }
  @Builder
  histBtn(label: string, kind: 'undo' | 'redo') {
    Button(label, { type: ButtonType.Normal })
      .attributeModifier(new ControlStyle(this.state.pal, 'quiet'))
      .onClick(() => this.actions.applyHistory(kind))
  }
  build() {
      // 预览只保留视图与导航；窄窗命令单行滚动。
      if (!this.state.compactHeight && (this.state.viewMode !== DefaultView.PREVIEW || this.state.bp !== 'phone')) {
        Scroll() {
          Row({ space: 4 }) {
            if (this.state.bp !== 'phone') {
              this.viewControls()
              this.toolSep()
            }
            if (this.state.viewMode !== DefaultView.PREVIEW) {
            this.toolGroup('标题')
            this.toolGroup('格式')
            this.toolGroup('段落')
            this.toolGroup('插入')
            this.toolSep()
            this.histBtn('撤销', 'undo')
            this.histBtn('重做', 'redo')
            }
            if (this.state.bp !== 'phone') {
              this.toolSep()
              this.navigationTools()
            }
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .align(Alignment.Start)
        .scrollBar(BarState.Auto)
        .width('100%')
        .height(ControlMetrics.HEIGHT)
      }

  }
}
