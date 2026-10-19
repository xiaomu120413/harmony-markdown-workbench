import { SafePage } from '../components/SafePage';
import { ControlStyle } from '../common/ControlStyle';
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { beginWindowMove } from '../common/WindowDrag';
import { ThemeMode, DefaultView } from '../domain/settings/AppSettings';
import { SegBtn } from '../common/SegBtn';
import { SettingsState } from '../features/settings/SettingsState';
import { SettingsViewModel } from '../features/settings/SettingsViewModel';
@Entry
@Component
struct SettingsPage {
  @State state: SettingsState = new SettingsState();
  @StorageProp('titleControlsBottom') captionBottom: number = 0;
  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private actions: SettingsViewModel = new SettingsViewModel(this.state, this.ctx);
  aboutToAppear(): void { this.actions = new SettingsViewModel(this.state, this.ctx); this.actions.load(); }
  aboutToDisappear(): void { this.actions.dispose(); }
  /** 区块标题（分组外的灰色小标题） */
  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.state.pal.TEXT_SUB)
      .padding({ left: 14, top: 14, bottom: 6 })
      .width('100%')
  }

  /** 行底部分隔线（组内最后一行不传） */
  @Builder
  rowDiv(show: boolean) {
    if (show) {
      Row() {}
        .width('100%')
        .height(1)
        .backgroundColor(this.state.pal.DIVIDER)
        .margin({ left: 16 })
    }
  }

  /** 标签列（主 + 说明） */
  @Builder
  rowLabel(label: string, sub: string, fullWidth: boolean = false) {
    Column({ space: 2 }) {
      Text(label).fontSize(15).fontColor(this.state.pal.TEXT)
      if (sub.length > 0) {
        Text(sub).fontSize(11).fontColor(this.state.pal.TEXT_FAINT)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(fullWidth ? 0 : 1)
    .constraintSize({ minWidth: fullWidth ? '100%' : 0 })
    .padding({ bottom: fullWidth ? 6 : 0 })
  }

  @Builder
  pageContent() {
    Column() {
      Column() {
        // 顶栏
        Row({ space: 8 }) {
          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20).fontColor([this.state.pal.TEXT])
          }
            .attributeModifier(new ControlStyle(this.state.pal, 'quiet', true)).accessibilityText('返回')
            .onClick(() => router.back())
          Text('设置')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.state.pal.TEXT)
            .padding({ top: 6, bottom: 6 })
            .onTouch((e: TouchEvent) => {
              // 系统标题栏已隐藏：标题区接管窗口拖动（否则本页窗口无法移动）
              if (e.type === TouchType.Down) {
                beginWindowMove(this.ctx);
              }
            })
        }
        .width('100%')
        .padding({ left: 4, top: 2 })

        Scroll() {
          Column() {
            // ---- 外观 ----
            this.sectionTitle('外观')
            Column() {
              Row({ space: 12 }) {
                this.rowLabel('主题', '')
                SegBtn({ label: '浅色', active: this.state.themeMode === ThemeMode.LIGHT, pal: this.state.pal, action: () => {
                  this.actions.setTheme(ThemeMode.LIGHT);
                } })
                SegBtn({ label: '深色', active: this.state.themeMode === ThemeMode.DARK, pal: this.state.pal, action: () => {
                  this.actions.setTheme(ThemeMode.DARK);
                } })
              }
              .width('100%')
              .constraintSize({ minHeight: 52 })
              .padding({ left: 16, right: 14 })
              this.rowDiv(true)

              Row({ space: 10 }) {
                this.rowLabel('字号', '编辑器与预览文字大小')
                SegBtn({ label: '−', active: false, pal: this.state.pal, action: () => {
                  this.actions.adjustFont(-1);
                } })
                Text(`${this.state.fontSize}`)
                  .fontSize(14)
                  .fontColor(this.state.pal.TEXT)
                  .width(28)
                  .textAlign(TextAlign.Center)
                SegBtn({ label: '+', active: false, pal: this.state.pal, action: () => {
                  this.actions.adjustFont(1);
                } })
                Text('px')
                  .fontSize(12)
                  .fontColor(this.state.pal.TEXT_FAINT)
              }
              .width('100%')
              .constraintSize({ minHeight: 52 })
              .padding({ left: 16, right: 14 })
            }
            .width('100%')
            .backgroundColor(this.state.pal.CONTENT)
            .borderRadius(12)
            .alignItems(HorizontalAlign.Start)

            // ---- 编辑器 ----
            this.sectionTitle('编辑器')
            Column() {
              Row({ space: 12 }) {
                this.rowLabel('自动换行', '')
                Toggle({ type: ToggleType.Switch, isOn: this.state.wrap })
                  .selectedColor(this.state.pal.PRIMARY)
                  .onChange((v: boolean) => { this.actions.setWrap(v); })
              }
              .width('100%')
              .constraintSize({ minHeight: 52 })
              .padding({ left: 16, right: 14 })
              this.rowDiv(true)

              Row({ space: 12 }) {
                this.rowLabel('显示行号', '')
                Toggle({ type: ToggleType.Switch, isOn: this.state.lineNumbers })
                  .selectedColor(this.state.pal.PRIMARY)
                  .onChange((v: boolean) => { this.actions.setLineNumbers(v); })
              }
              .width('100%')
              .constraintSize({ minHeight: 52 })
              .padding({ left: 16, right: 14 })
              this.rowDiv(true)

              Row({ space: 12 }) {
                this.rowLabel('自动保存', '停止输入片刻后自动写入文件')
                Toggle({ type: ToggleType.Switch, isOn: this.state.autoSave })
                  .selectedColor(this.state.pal.PRIMARY)
                  .onChange((v: boolean) => { this.actions.setAutoSave(v); })
              }
              .width('100%')
              .constraintSize({ minHeight: 52 })
              .padding({ left: 16, right: 14 })
              this.rowDiv(true)

              Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
                this.rowLabel('默认视图', '平板与电脑可选分屏', this.state.narrow)
                Row({ space: 6 }) {
                SegBtn({ label: '编辑', active: this.state.defaultView === DefaultView.EDIT, pal: this.state.pal, action: () => {
                  this.actions.setDefaultView(DefaultView.EDIT);
                } })
                SegBtn({ label: '预览', active: this.state.defaultView === DefaultView.PREVIEW, pal: this.state.pal, action: () => {
                  this.actions.setDefaultView(DefaultView.PREVIEW);
                } })
                SegBtn({ label: '分屏', active: this.state.defaultView === DefaultView.SPLIT, pal: this.state.pal, action: () => {
                  this.actions.setDefaultView(DefaultView.SPLIT);
                } })
                }
              }
              .width('100%')
              .constraintSize({ minHeight: 56 })
              .padding({ left: 16, right: 14, top: 8, bottom: 8 })
            }
            .width('100%')
            .backgroundColor(this.state.pal.CONTENT)
            .borderRadius(12)
            .alignItems(HorizontalAlign.Start)

            // ---- 数据 ----
            this.sectionTitle('数据')
            Column() {
              Row({ space: 12 }) {
                this.rowLabel('未保存草稿', '应用意外退出时自动保留')
                Text(`${this.state.draftCount} 个`)
                  .fontSize(14)
                  .fontColor(this.state.pal.TEXT_SUB)
              }
              .width('100%')
              .constraintSize({ minHeight: 52 })
              .padding({ left: 16, right: 14 })
              this.rowDiv(true)

              Button(this.state.draftCount > 0 ? '查看并恢复草稿' : '打开恢复页', { type: ButtonType.Normal })
                .width(180)
                .margin({ left: 16, top: 10, bottom: 12 })
                .attributeModifier(new ControlStyle(this.state.pal, 'secondary'))
                .onClick(() => router.pushUrl({ url: 'pages/RecoveryPage' }))
            }
            .width('100%')
            .backgroundColor(this.state.pal.CONTENT)
            .borderRadius(12)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding({ bottom: 24 })
        }
        .layoutWeight(1)
        .align(Alignment.TopStart)
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .constraintSize({ maxWidth: 760 })
      .height('100%')
    }
    .width('100%')
    .height('100%').padding({ top: this.captionBottom })
    .onAreaChange((_old: Area, area: Area) => { this.state.narrow = (area.width as number) < 600; })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.state.pal.BG)
  }
  build() { Column() { SafePage() { this.pageContent() } }.width('100%').height('100%') }
}
