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
  @StorageProp('colorMode') @Watch('colorModeChanged') colorMode: number = -1;
  private colorModeChanged(): void { this.actions.refreshTheme(); }
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
  helpItem(title: string, description: string) {
    Column({ space: 5 }) {
      Text(title).fontSize(15).fontColor(this.state.pal.TEXT)
      Text(description).fontSize(13).fontColor(this.state.pal.TEXT_SUB).lineHeight(21)
    }
    .alignItems(HorizontalAlign.Start).width('100%').padding(16)
  }

  @Builder
  shortcut(label: string, keys: string) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
      Text(label).fontSize(14).fontColor(this.state.pal.TEXT).padding({ right: 12, top: 6, bottom: 6 })
      Text(keys).fontSize(13).fontColor(this.state.pal.TEXT_SUB).padding({ top: 6, bottom: 6 })
    }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: 4 })
  }

  @Builder
  helpContent() {
    this.sectionTitle('使用帮助')
    Column() {
      this.helpItem('打开与拖入', '通过“打开文件”编辑外部原文件；拖入文档会导入“我的文档”，编辑的是应用内副本。')
      this.rowDiv(true)
      this.helpItem('保存与带走文档', '“保存”写回当前文件；“另存为”切换保存位置。带图片的文档请导出图文 ZIP，单个 Markdown 文件仅包含正文；HTML 可用于阅读分享。')
      this.rowDiv(true)
      this.helpItem('文件授权与数据保留', '仅访问你选择的文件，并尝试保留访问授权。授权失效时请重新选择原文件。“我的文档”和恢复草稿保存在应用内，卸载前请先导出。')
      this.rowDiv(true)
      this.helpItem('编辑与视图', '工具栏按标题、格式、段落和插入分组；再次选择同级标题可取消。查找支持替换，大纲可跳转标题；平板与电脑可并排编辑和预览。')
    }
    .width('100%').backgroundColor(this.state.pal.CONTENT).borderRadius(12)
    this.sectionTitle('外接键盘快捷键')
    Column() {
      this.shortcut('保存', 'Ctrl + S')
      this.shortcut('焦点 / 激活', 'Tab / Shift+Tab / Enter / Space')
      this.rowDiv(true)
      this.shortcut('查找 / 大纲', 'Ctrl + F / Ctrl + Shift + F')
      this.shortcut('关闭查找 / 系统菜单', 'Esc / Shift + F10')
      this.rowDiv(true)
      this.shortcut('加粗 / 斜体', 'Ctrl + B / Ctrl + I')
      this.rowDiv(true)
      this.shortcut('撤销 / 重做', 'Ctrl + Z / Ctrl + Y')
    }
    .width('100%').backgroundColor(this.state.pal.CONTENT).borderRadius(12)
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
              Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
                this.rowLabel('主题', '', this.state.narrow)
                SegBtn({ label: '跟随系统', active: this.state.themeMode === ThemeMode.SYSTEM, pal: this.state.pal, action: () => {
                  this.actions.setTheme(ThemeMode.SYSTEM);
                } })
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
            this.helpContent()
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
