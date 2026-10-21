import { DocumentSidebar } from '../../components/DocumentSidebar';
import { EditorHeader } from './EditorHeader';
import { EditorFindPanel } from './EditorFindPanel';
import { EditorCommandBar } from './EditorCommandBar';
import { EditorWorkspace } from './EditorWorkspace';
import { ControlStyle } from '../../common/ControlStyle';
import { EditorState } from './EditorState';
import { EditorController } from './EditorController';

@Component
export struct EditorScreen {
  @ObjectLink state: EditorState;
  @Require actions: EditorController;
  build() {
    Column({ space: 8 }) {
      EditorHeader({ state: this.state, actions: this.actions })
      EditorFindPanel({ state: this.state, actions: this.actions })
      // 冲突条（M4-03；wrap 防溢出）
      if (this.state.conflictVisible) {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Text('⚠ 磁盘版本已变化（自动保存已停止）')
            .fontSize(12)
            .fontColor(this.state.pal.DANGER)
          Button('用磁盘版', { type: ButtonType.Normal })
            .attributeModifier(new ControlStyle(this.state.pal, 'quiet')).onClick(() => this.actions.conflictKeepDisk())
          Button('保留本地', { type: ButtonType.Normal })
            .attributeModifier(new ControlStyle(this.state.pal, 'quiet')).onClick(() => this.actions.conflictKeepLocal())
          Button('另存副本', { type: ButtonType.Normal })
            .attributeModifier(new ControlStyle(this.state.pal, 'quiet')).onClick(() => this.actions.conflictSaveCopy())
        }
        .width('100%')
        .padding(6)
        .backgroundColor(this.state.pal.DANGER_SOFT)
        .borderRadius(8)
      }

      EditorCommandBar({ state: this.state, actions: this.actions })
      Row({ space: 0 }) {
        // B1/B2：文档侧栏（编辑页内切换文档，phone 档可折叠）
        if (this.state.sidebarVisible && this.state.bp !== 'phone' &&
          this.state.loadState !== 'loadFailed' && this.state.loadState !== 'accessExpired') {
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

        Column({ space: 8 }) {
          EditorWorkspace({ state: this.state, actions: this.actions }).layoutWeight(1)
          // 状态栏（V0.4.2：字数 + 光标行列，备忘录式底部信息条）
          if (!this.state.compactHeight || this.state.recoveryLabel.includes('失败')) {
          Row() {
            if (this.state.dropBusy) { Text('正在读取拖入文件…').fontSize(11).fontColor(this.state.pal.PRIMARY) }
            Text(this.state.recoveryLabel).fontSize(11).fontColor(this.state.pal.TEXT_SUB).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            Text(`${this.state.docLength} 字`)
              .fontSize(11)
              .fontColor(this.state.pal.TEXT_FAINT)
            if (this.state.bp !== 'phone') {
            Text(`行 ${this.state.cursorLine}，列 ${this.state.cursorCol}`)
              .fontSize(11)
              .fontColor(this.state.pal.TEXT_FAINT)
              .padding({ left: 12 })
            }
            Blank()
            if (this.state.bp !== 'phone' && this.state.outlineEntries.length > 0) {
              Text(`${this.state.outlineEntries.length} 个标题`)
                .fontSize(11)
                .fontColor(this.state.pal.TEXT_FAINT)
            }
          }
          .width('100%')
          .height(26)
          .padding({ left: 4, right: 4 })
          }
        }.layoutWeight(1).height('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').alignItems(VerticalAlign.Top)
    }
    .padding({ top: 12, left: 12, right: 12, bottom: 0 })
    .width('100%')
    .height('100%')
    .backgroundColor(this.state.pal.CONTENT)
    .onDragEnter(() => { this.state.fileHover = true; })
    .onDragLeave(() => { this.state.fileHover = false; })
    .onDrop((event: DragEvent) => { this.actions.receiveDrop(event); }, { disableDataPrefetch: true })
    .onAreaChange((_old: Area, newArea: Area) => {
      // B2-05/B4：实际 vp 尺寸驱动空间决策（不以设备类型或整块屏幕分辨率决定）
      this.state.compactHeight = (newArea.height as number) < 480;
      this.state.contentWidthVp = Math.max(0, (newArea.width as number) - 24);
      // B4-01：空间不足时自动降级分屏 → 编辑（偏好不覆盖，空间恢复后可重新切换）
      this.actions.enforceWorkspaceBudget();
    })
  }
}
