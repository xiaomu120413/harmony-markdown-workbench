import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';
import { AppSettings, SettingsValidator, ThemeMode, DefaultView } from '../domain/settings/AppSettings';
import { SettingsStore } from '../infrastructure/metadata/SettingsStore';
import { DraftStore } from '../infrastructure/metadata/DraftStore';
import { AppTheme } from '../common/AppTheme';
import { SegBtn } from '../common/SegBtn';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-SETTINGS';

/**
 * 设置页（M5-03 产品化）：外观 / 编辑器 / 数据 三区。
 * 即改即存（无保存按钮）；主题切换即时生效（本页 + 返回首页/编辑器时跟随）；
 * 非法值由 SettingsValidator 回退（重启保持）。
 */
@Entry
@Component
struct SettingsPage {
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

  /** 即改即存：任何设置变更立即持久化（静默，无确认弹窗） */
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

  /** 区块标题 */
  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.pal.TEXT_SUB)
      .padding({ left: 4, top: 8, bottom: 4 })
      .width('100%')
  }

  /** 设置行（左标签 + 说明） */
  @Builder
  settingRow(label: string, sub: string) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(label).fontSize(15).fontColor(this.pal.TEXT)
        if (sub.length > 0) {
          Text(sub).fontSize(11).fontColor(this.pal.TEXT_FAINT)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Blank()
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }

  build() {
    // 外层全宽容器负责水平居中（页面根上的 alignSelf 不生效，宽窗口下会左贴边）
    Column() {
    Column({ space: 0 }) {
      // 顶栏
      Row({ space: 8 }) {
        Button('‹')
          .fontSize(22)
          .fontColor(this.pal.TEXT)
          .backgroundColor(this.pal.TOOLBAR_BG)
          .borderRadius(10)
          .width(40)
          .height(40)
          .onClick(() => router.back())
        Text('设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.TEXT)
      }
      .width('100%')

      Scroll() {
        Column() {
          // ---- 外观 ----
          this.sectionTitle('外观')
          Column({ space: 0 }) {
            this.settingRow('主题', '深色模式下全应用跟随')
            Row({ space: 8 }) {
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
            .padding({ bottom: 12 })

            this.settingRow('字号', `${this.fontSize} px`)
            Row({ space: 8 }) {
              SegBtn({ label: '−', active: false, pal: this.pal, action: () => {
                this.fontSize = SettingsValidator.clampFont(this.fontSize - 1);
                this.persist();
              } })
              SegBtn({ label: '+', active: false, pal: this.pal, action: () => {
                this.fontSize = SettingsValidator.clampFont(this.fontSize + 1);
                this.persist();
              } })
            }
            .padding({ bottom: 12 })
          }
          .width('100%')
          .padding({ left: 14, right: 14 })
          .backgroundColor(this.pal.CARD)
          .borderRadius(12)

          // ---- 编辑器 ----
          this.sectionTitle('编辑器')
          Column({ space: 0 }) {
            Row({ space: 12 }) {
              Text('自动换行').fontSize(15).fontColor(this.pal.TEXT).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.wrap })
                .onChange((v: boolean) => { this.wrap = v; this.persist(); })
            }
            .width('100%')
            .padding({ top: 10, bottom: 10 })

            Row({ space: 12 }) {
              Text('显示行号').fontSize(15).fontColor(this.pal.TEXT).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.lineNumbers })
                .onChange((v: boolean) => { this.lineNumbers = v; this.persist(); })
            }
            .width('100%')
            .padding({ top: 10, bottom: 10 })

            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text('自动保存').fontSize(15).fontColor(this.pal.TEXT)
                Text('停止输入片刻后自动写入文件').fontSize(11).fontColor(this.pal.TEXT_FAINT)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.autoSave })
                .onChange((v: boolean) => { this.autoSave = v; this.persist(); })
            }
            .width('100%')
            .padding({ top: 10, bottom: 10 })

            this.settingRow('默认视图', '平板与电脑上可选分屏')
            Row({ space: 8 }) {
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
            .padding({ bottom: 12 })
          }
          .width('100%')
          .padding({ left: 14, right: 14 })
          .backgroundColor(this.pal.CARD)
          .borderRadius(12)

          // ---- 数据 ----
          this.sectionTitle('数据')
          Column({ space: 0 }) {
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text('未保存草稿').fontSize(15).fontColor(this.pal.TEXT)
                Text('意外退出时自动保留的内容').fontSize(11).fontColor(this.pal.TEXT_FAINT)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text(`${this.draftCount} 个`)
                .fontSize(14)
                .fontColor(this.pal.TEXT_SUB)
            }
            .width('100%')
            .padding({ top: 10, bottom: 10 })

            Button(this.draftCount > 0 ? '查看并恢复草稿' : '打开恢复页')
              .fontSize(14)
              .fontColor(this.pal.ON_PRIMARY)
              .backgroundColor(this.pal.PRIMARY)
              .borderRadius(8)
              .width('100%')
              .height(40)
              .margin({ top: 4, bottom: 12 })
              .onClick(() => router.pushUrl({ url: 'pages/RecoveryPage' }))
          }
          .width('100%')
          .padding({ left: 14, right: 14 })
          .backgroundColor(this.pal.CARD)
          .borderRadius(12)
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .constraintSize({ maxWidth: 760 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.pal.BG)
  }
}
