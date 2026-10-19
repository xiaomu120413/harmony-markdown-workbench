import { SafePage } from '../components/SafePage';
import { ControlStyle } from '../common/ControlStyle';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';
import { beginWindowMove } from '../common/WindowDrag';
import { AppSettings, SettingsValidator, ThemeMode, DefaultView } from '../domain/settings/AppSettings';
import { SettingsStore } from '../infrastructure/metadata/SettingsStore';
import { DraftStore } from '../infrastructure/metadata/DraftStore';
import { AppTheme } from '../common/AppTheme';
import { SegBtn } from '../common/SegBtn';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-SETTINGS';

/**
 * 设置页（V0.4：对齐系统设置的原生分组行样式）。
 * 灰底页面 + 白底圆角分组；行内左标签右控件，行间细分隔线；
 * 即改即存；主题切换即时生效。
 */
@Entry
@Component
struct SettingsPage {
  @State narrow: boolean = true;
  @StorageProp('titleControlsBottom') captionBottom: number = 0;
  @State themeMode: ThemeMode = ThemeMode.LIGHT;
  @State fontSize: number = 15;
  @State wrap: boolean = true;
  @State lineNumbers: boolean = true;
  @State autoSave: boolean = true;
  @State defaultView: DefaultView = DefaultView.EDIT;
  @State draftCount: number = 0;
  @State pal: AppTheme = AppTheme.light();
  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private store: SettingsStore = new SettingsStore(getContext(this) as common.UIAbilityContext);

  private note(line: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', line);
  }

  async aboutToAppear(): Promise<void> {
    const s = await this.store.load();
    this.themeMode = s.theme;
    this.fontSize = s.fontSize;
    this.wrap = s.wrap;
    this.lineNumbers = s.lineNumbers;
    this.autoSave = s.autoSave;
    this.defaultView = s.defaultView;
    this.pal = AppTheme.of(s.theme === ThemeMode.DARK);
    try {
      const drafts = new DraftStore(this.ctx);
      this.draftCount = drafts.listAll().length;
    } catch (e) {
      this.draftCount = 0;
    }
  }

  /** 即改即存：任何设置变更立即持久化（静默） */
  private persist(): void {
    const s: AppSettings = {
      theme: this.themeMode,
      fontSize: SettingsValidator.clampFont(this.fontSize),
      wrap: this.wrap,
      lineNumbers: this.lineNumbers,
      autoSave: this.autoSave,
      defaultView: this.defaultView,
    };
    this.store.save(s);
    this.note(`[设置] theme=${s.theme} font=${s.fontSize} wrap=${s.wrap} lines=${s.lineNumbers} auto=${s.autoSave} view=${s.defaultView}`);
  }

  /** 区块标题（分组外的灰色小标题） */
  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.pal.TEXT_SUB)
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
        .backgroundColor(this.pal.DIVIDER)
        .margin({ left: 16 })
    }
  }

  /** 标签列（主 + 说明） */
  @Builder
  rowLabel(label: string, sub: string, fullWidth: boolean = false) {
    Column({ space: 2 }) {
      Text(label).fontSize(15).fontColor(this.pal.TEXT)
      if (sub.length > 0) {
        Text(sub).fontSize(11).fontColor(this.pal.TEXT_FAINT)
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
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20).fontColor([this.pal.TEXT])
          }
            .attributeModifier(new ControlStyle(this.pal, 'quiet', true)).accessibilityText('返回')
            .onClick(() => router.back())
          Text('设置')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.TEXT)
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
                SegBtn({ label: '浅色', active: this.themeMode === ThemeMode.LIGHT, pal: this.pal, action: () => {
                  this.themeMode = ThemeMode.LIGHT;
                  this.pal = AppTheme.light();
                  this.persist();
                } })
                SegBtn({ label: '深色', active: this.themeMode === ThemeMode.DARK, pal: this.pal, action: () => {
                  this.themeMode = ThemeMode.DARK;
                  this.pal = AppTheme.dark();
                  this.persist();
                } })
              }
              .width('100%')
              .constraintSize({ minHeight: 52 })
              .padding({ left: 16, right: 14 })
              this.rowDiv(true)

              Row({ space: 10 }) {
                this.rowLabel('字号', '编辑器与预览文字大小')
                SegBtn({ label: '−', active: false, pal: this.pal, action: () => {
                  this.fontSize = SettingsValidator.clampFont(this.fontSize - 1);
                  this.persist();
                } })
                Text(`${this.fontSize}`)
                  .fontSize(14)
                  .fontColor(this.pal.TEXT)
                  .width(28)
                  .textAlign(TextAlign.Center)
                SegBtn({ label: '+', active: false, pal: this.pal, action: () => {
                  this.fontSize = SettingsValidator.clampFont(this.fontSize + 1);
                  this.persist();
                } })
                Text('px')
                  .fontSize(12)
                  .fontColor(this.pal.TEXT_FAINT)
              }
              .width('100%')
              .constraintSize({ minHeight: 52 })
              .padding({ left: 16, right: 14 })
            }
            .width('100%')
            .backgroundColor(this.pal.CONTENT)
            .borderRadius(12)
            .alignItems(HorizontalAlign.Start)

            // ---- 编辑器 ----
            this.sectionTitle('编辑器')
            Column() {
              Row({ space: 12 }) {
                this.rowLabel('自动换行', '')
                Toggle({ type: ToggleType.Switch, isOn: this.wrap })
                  .selectedColor(this.pal.PRIMARY)
                  .onChange((v: boolean) => { this.wrap = v; this.persist(); })
              }
              .width('100%')
              .constraintSize({ minHeight: 52 })
              .padding({ left: 16, right: 14 })
              this.rowDiv(true)

              Row({ space: 12 }) {
                this.rowLabel('显示行号', '')
                Toggle({ type: ToggleType.Switch, isOn: this.lineNumbers })
                  .selectedColor(this.pal.PRIMARY)
                  .onChange((v: boolean) => { this.lineNumbers = v; this.persist(); })
              }
              .width('100%')
              .constraintSize({ minHeight: 52 })
              .padding({ left: 16, right: 14 })
              this.rowDiv(true)

              Row({ space: 12 }) {
                this.rowLabel('自动保存', '停止输入片刻后自动写入文件')
                Toggle({ type: ToggleType.Switch, isOn: this.autoSave })
                  .selectedColor(this.pal.PRIMARY)
                  .onChange((v: boolean) => { this.autoSave = v; this.persist(); })
              }
              .width('100%')
              .constraintSize({ minHeight: 52 })
              .padding({ left: 16, right: 14 })
              this.rowDiv(true)

              Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
                this.rowLabel('默认视图', '平板与电脑可选分屏', this.narrow)
                Row({ space: 6 }) {
                SegBtn({ label: '编辑', active: this.defaultView === DefaultView.EDIT, pal: this.pal, action: () => {
                  this.defaultView = DefaultView.EDIT;
                  this.persist();
                } })
                SegBtn({ label: '预览', active: this.defaultView === DefaultView.PREVIEW, pal: this.pal, action: () => {
                  this.defaultView = DefaultView.PREVIEW;
                  this.persist();
                } })
                SegBtn({ label: '分屏', active: this.defaultView === DefaultView.SPLIT, pal: this.pal, action: () => {
                  this.defaultView = DefaultView.SPLIT;
                  this.persist();
                } })
                }
              }
              .width('100%')
              .constraintSize({ minHeight: 56 })
              .padding({ left: 16, right: 14, top: 8, bottom: 8 })
            }
            .width('100%')
            .backgroundColor(this.pal.CONTENT)
            .borderRadius(12)
            .alignItems(HorizontalAlign.Start)

            // ---- 数据 ----
            this.sectionTitle('数据')
            Column() {
              Row({ space: 12 }) {
                this.rowLabel('未保存草稿', '应用意外退出时自动保留')
                Text(`${this.draftCount} 个`)
                  .fontSize(14)
                  .fontColor(this.pal.TEXT_SUB)
              }
              .width('100%')
              .constraintSize({ minHeight: 52 })
              .padding({ left: 16, right: 14 })
              this.rowDiv(true)

              Button(this.draftCount > 0 ? '查看并恢复草稿' : '打开恢复页', { type: ButtonType.Normal })
                .width(180)
                .margin({ left: 16, top: 10, bottom: 12 })
                .attributeModifier(new ControlStyle(this.pal, 'secondary'))
                .onClick(() => router.pushUrl({ url: 'pages/RecoveryPage' }))
            }
            .width('100%')
            .backgroundColor(this.pal.CONTENT)
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
    .onAreaChange((_old: Area, area: Area) => { this.narrow = (area.width as number) < 600; })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.pal.BG)
  }
  build() { Column() { SafePage() { this.pageContent() } }.width('100%').height('100%') }
}
