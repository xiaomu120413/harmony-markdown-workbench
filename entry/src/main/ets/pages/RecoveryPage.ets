import { SafePage } from '../components/SafePage';
import { ControlStyle, ControlMetrics } from '../common/ControlStyle';
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { RecoveryDecision } from '../domain/recovery/DraftDecision';
import { beginWindowMove } from '../common/WindowDrag';
import { RecoveryState, DraftRow } from '../features/recovery/RecoveryState';
import { RecoveryViewModel } from '../features/recovery/RecoveryViewModel';
@Entry
@Component
struct RecoveryPage {
  @StorageProp('titleControlsBottom') captionBottom: number = 0;
  @State state: RecoveryState = new RecoveryState();
  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private actions: RecoveryViewModel = new RecoveryViewModel(this.state, this.ctx);
  aboutToAppear(): void { this.actions = new RecoveryViewModel(this.state, this.ctx); this.actions.load(); }
  aboutToDisappear(): void { this.actions.dispose(); }
  @Builder
  pageContent() {
    // 外层全宽容器负责水平居中（页面根上的 alignSelf 不生效）
    Column() {
    Stack({ alignContent: Alignment.Top }) {
      Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20).fontColor([this.state.pal.TEXT])
        }
          .attributeModifier(new ControlStyle(this.state.pal, 'quiet', true)).accessibilityText('返回')
          .onClick(() => router.back())
        Text('找回未保存内容')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.state.pal.TEXT)
          .padding({ top: 6, bottom: 6 })
          .onTouch((e: TouchEvent) => {
            // 系统标题栏已隐藏：标题区接管窗口拖动
            if (e.type === TouchType.Down) {
              beginWindowMove(this.ctx);
            }
          })
        Blank()
      }
      .width('100%')

      if (this.state.rows.length === 0) {
        Text('没有需要恢复的内容。\n应用意外退出时，未保存的内容会自动保留在这里。')
          .fontSize(13)
          .fontColor(this.state.pal.TEXT_SUB)
          .width('100%')
      }

      List({ space: 8 }) {
        ForEach(this.state.rows, (row: DraftRow) => {
          ListItem() {
            Column({ space: 4 }) {
              Row({ space: 8 }) {
                Text(this.actions.documentName(row.draft.sourceFingerprint))
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.state.pal.TEXT)
                  .layoutWeight(1)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.actions.fmtTime(row.draft.updatedAt))
                  .fontSize(12)
                  .fontColor(this.state.pal.TEXT_SUB)
                  .constraintSize({ minWidth: 110 }).maxLines(1)
              }
              .width('100%')

              Text(row.decisionName)
                .fontSize(11)
                .fontColor(row.decision === RecoveryDecision.CONFLICT ? this.state.pal.DANGER : this.state.pal.OK)

              Text(row.draft.content.substring(0, 100).replace(/\n/g, '⏎'))
                .fontSize(11)
                .fontColor(this.state.pal.TEXT_FAINT)
                .maxLines(2)

              Flex({ wrap: FlexWrap.Wrap }) {
                if (row.decision === RecoveryDecision.RESTORE_DRAFT) {
                  Button('恢复', { type: ButtonType.Normal })
                    .attributeModifier(new ControlStyle(this.state.pal, 'primary'))
                    .width(96).margin({ right: 8, top: 4 }).onClick(() => this.actions.restoreRow(row))
                }
                Button('另存副本', { type: ButtonType.Normal })
                  .attributeModifier(new ControlStyle(this.state.pal, 'quiet'))
                  .width(96).margin({ right: 8, top: 4 }).onClick(() => this.actions.saveCopy(row))
                Button(row.decision === RecoveryDecision.DISCARD_REDUNDANT ? '确认清理' : '放弃草稿', { type: ButtonType.Normal })
                  .attributeModifier(new ControlStyle(this.state.pal, 'danger'))
                  .width(96).margin({ right: 8, top: 4 }).onClick(() => this.actions.discardRow(row))
              }
              .width('100%')
            }
            .padding(10)
            .backgroundColor(this.state.pal.CONTENT)
            .borderRadius(ControlMetrics.RADIUS)
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
        }, (row: DraftRow) => row.draft.documentId)
      }
      .layoutWeight(1)
      .width('100%')
      }
      .padding(16)
      .width('100%')
      .constraintSize({ maxWidth: 760 })
      .height('100%')
      .backgroundColor(this.state.pal.BG)
    }
    }
    .width('100%')
    .height('100%').padding({ top: this.captionBottom })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.state.pal.BG)
  }
  build() { Column() { SafePage() { this.pageContent() } }.width('100%').height('100%') }
}
