import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';
import { AppSettings, SettingsValidator, ThemeMode, DefaultView } from '../domain/settings/AppSettings';
import { SettingsStore } from '../infrastructure/metadata/SettingsStore';
import { DraftStore } from '../infrastructure/metadata/DraftStore';
import { AppTheme } from '../common/AppTheme';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-SETTINGS';

/**
 * M5-03 设置页：主题/字号/自动换行/行号/自动保存/默认视图/恢复草稿管理。
 * 持久化 preferences；非法值由 SettingsValidator 回退（重启保持）。
 * 主题/字号等在编辑器内即时生效（EditorPage aboutToAppear 读取应用），本页修改即存。
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
  @State log: string = '';
  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private store: SettingsStore = new SettingsStore(getContext(this) as common.UIAbilityContext);

  private append(line: string): void {
    this.log = `${line}\n---\n${this.log}`;
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
    try {
      const drafts = new DraftStore(this.ctx);
      this.draftCount = drafts.listAll().length;
    } catch (e) {
      this.draftCount = 0;
    }
  }

  private async persist(): Promise<void> {
    const s: AppSettings = {
      theme: this.themeMode,
      fontSize: SettingsValidator.clampFont(this.fontSize),
      wrap: this.wrap,
      lineNumbers: this.lineNumbers,
      autoSave: this.autoSave,
      defaultView: this.defaultView,
    };
    await this.store.save(s);
    this.append('[设置] 已保存（恢复草稿数 ' + this.draftCount + '）');
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Button('返回')
          .fontSize(13)
          .onClick(() => router.back())
        Text('设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT)
        Blank()
        Button('保存')
          .fontSize(13)
          .fontColor(AppTheme.ON_PRIMARY)
          .backgroundColor(AppTheme.PRIMARY)
          .borderRadius(8)
          .onClick(() => this.persist())
      }
      .width('100%')

      Scroll() {
        Column({ space: 6 }) {
          Text('主题').fontSize(14)
          Row({ space: 8 }) {
            Button('浅色').fontSize(13)
              .backgroundColor(this.themeMode === ThemeMode.LIGHT ? AppTheme.PRIMARY : '#33000000')
              .onClick(() => { this.themeMode = ThemeMode.LIGHT; })
            Button('深色').fontSize(13)
              .backgroundColor(this.themeMode === ThemeMode.DARK ? AppTheme.PRIMARY : '#33000000')
              .onClick(() => { this.themeMode = ThemeMode.DARK; })
          }

          Text(`字号：${this.fontSize} px`).fontSize(14)
          Row({ space: 8 }) {
            Button('−').fontSize(15).onClick(() => {
              this.fontSize = SettingsValidator.clampFont(this.fontSize - 1);
            })
            Button('+').fontSize(15).onClick(() => {
              this.fontSize = SettingsValidator.clampFont(this.fontSize + 1);
            })
          }

          Row({ space: 8 }) {
            Text('自动换行').fontSize(14)
            Toggle({ type: ToggleType.Switch, isOn: this.wrap })
              .onChange((v: boolean) => { this.wrap = v; })
          }
          .width('100%')

          Row({ space: 8 }) {
            Text('行号').fontSize(14)
            Toggle({ type: ToggleType.Switch, isOn: this.lineNumbers })
              .onChange((v: boolean) => { this.lineNumbers = v; })
          }
          .width('100%')

          Row({ space: 8 }) {
            Text('自动保存').fontSize(14)
            Toggle({ type: ToggleType.Switch, isOn: this.autoSave })
              .onChange((v: boolean) => { this.autoSave = v; })
          }
          .width('100%')

          Text('默认视图').fontSize(14)
          Row({ space: 8 }) {
            Button('编辑').fontSize(13)
              .backgroundColor(this.defaultView === DefaultView.EDIT ? AppTheme.PRIMARY : '#33000000')
              .onClick(() => { this.defaultView = DefaultView.EDIT; })
            Button('预览').fontSize(13)
              .backgroundColor(this.defaultView === DefaultView.PREVIEW ? AppTheme.PRIMARY : '#33000000')
              .onClick(() => { this.defaultView = DefaultView.PREVIEW; })
            Button('分屏').fontSize(13)
              .backgroundColor(this.defaultView === DefaultView.SPLIT ? AppTheme.PRIMARY : '#33000000')
              .onClick(() => { this.defaultView = DefaultView.SPLIT; })
          }

          Divider()

          Text(`恢复草稿管理（${this.draftCount} 个检查点）`).fontSize(14)
          Button('打开恢复页')
            .fontSize(13)
            .onClick(() => router.pushUrl({ url: 'pages/RecoveryPage' }))

          Text(this.log)
            .fontSize(10)
            .fontColor('#99000000')
            .maxLines(3)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG)
  }
}