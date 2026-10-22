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
  @State helpExpanded: boolean = false;
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
      .fontSize(14).fontWeight(FontWeight.Medium)
      .fontColor(this.state.pal.TEXT_SUB)
      .padding({ left: 4, top: 24, bottom: 10 })
      .width('100%')
  }

  /** 行底部分隔线（组内最后一行不传） */
  @Builder
  rowDiv(show: boolean) {
    if (show) {
      Row() {}
        .width('100%').height(0.5).backgroundColor(this.state.pal.DIVIDER)
    }
  }

  /** 标签列（主 + 说明） */
  @Builder
  rowLabel(label: string, sub: string, fullWidth: boolean = false) {
    Column({ space: 2 }) {
      Text(label).fontSize(15).fontColor(this.state.pal.TEXT)
      if (sub.length > 0) {
        Text(sub).fontSize(13).fontColor(this.state.pal.TEXT_SUB).lineHeight(19)
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
      this.helpItem('打开与拖入', 'Markdown 文档单独打开；拖入 TXT、图片或 HTML 会插入当前正文。通过“打开文档”选择外部原文件，可保存写回原位置。')
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
        .padding({ left: 16, right: 16, top: 8, bottom: 4 })

        Scroll() {
          Column() {
            // ---- 外观 ----
            this.sectionTitle('外观')
            Column() {
              Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
                this.rowLabel('主题', '为编辑区与预览选择外观', true)
                Row({ space: 4 }) {
                SegBtn({ label: '跟随系统', active: this.state.themeMode === ThemeMode.SYSTEM, pal: this.state.pal, action: () => {
                  this.actions.setTheme(ThemeMode.SYSTEM);
                } })
                SegBtn({ label: '浅色', active: this.state.themeMode === ThemeMode.LIGHT, pal: this.state.pal, action: () => {
                  this.actions.setTheme(ThemeMode.LIGHT);
                } })
                SegBtn({ label: '深色', active: this.state.themeMode === ThemeMode.DARK, pal: this.state.pal, action: () => {
                  this.actions.setTheme(ThemeMode.DARK);
                } })
                }.padding(4).backgroundColor(this.state.pal.CARD).borderRadius(10)
              }
              .width('100%')
              .constraintSize({ minHeight: 68 })
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
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
              .constraintSize({ minHeight: 68 })
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            }
            .width('100%')
            .backgroundColor(this.state.pal.CONTENT)
            .borderRadius(12)
            .alignItems(HorizontalAlign.Start)

            // ---- 编辑器 ----
            this.sectionTitle('编辑器')
            Column() {
              Row({ space: 12 }) {
                this.rowLabel('自动换行', '长段落随窗口宽度换行')
                Toggle({ type: ToggleType.Switch, isOn: this.state.wrap })
                  .selectedColor(this.state.pal.PRIMARY)
                  .onChange((v: boolean) => { this.actions.setWrap(v); })
              }
              .width('100%')
              .constraintSize({ minHeight: 68 })
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              this.rowDiv(true)

              Row({ space: 12 }) {
                this.rowLabel('显示行号', '在编辑区左侧显示行号')
                Toggle({ type: ToggleType.Switch, isOn: this.state.lineNumbers })
                  .selectedColor(this.state.pal.PRIMARY)
                  .onChange((v: boolean) => { this.actions.setLineNumbers(v); })
              }
              .width('100%')
              .constraintSize({ minHeight: 68 })
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              this.rowDiv(true)

              Row({ space: 12 }) {
                this.rowLabel('自动保存', '停止输入片刻后自动写入文件')
                Toggle({ type: ToggleType.Switch, isOn: this.state.autoSave })
                  .selectedColor(this.state.pal.PRIMARY)
                  .onChange((v: boolean) => { this.actions.setAutoSave(v); })
              }
              .width('100%')
              .constraintSize({ minHeight: 68 })
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              this.rowDiv(true)

              Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
                this.rowLabel('打开文档时的视图', '修改后返回文档即生效；分屏需要足够宽度', true)
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
                }.padding(4).backgroundColor(this.state.pal.CARD).borderRadius(10)
              }
              .width('100%')
              .constraintSize({ minHeight: 56 })
              .padding({ left: 16, right: 16, top: 16, bottom: 16 })
            }
            .width('100%')
            .backgroundColor(this.state.pal.CONTENT)
            .borderRadius(12)
            .alignItems(HorizontalAlign.Start)

            // ---- 数据 ----
            this.sectionTitle('草稿与帮助')
            Column() {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 12 }) {
                  this.rowLabel('恢复草稿', '查看意外退出前保留的内容')
                  Text(`${this.state.draftCount} 个`).fontSize(14).fontColor(this.state.pal.TEXT_SUB)
                  SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([this.state.pal.TEXT_SUB])
                }.width('100%')
              }.width('100%').constraintSize({ minHeight: 68 }).padding(16)
                .backgroundColor(Color.Transparent).borderRadius(12).hoverEffect(HoverEffect.Highlight)
                .onClick(() => router.pushUrl({ url: 'pages/RecoveryPage' }))
              this.rowDiv(true)
              Button({ type: ButtonType.Normal }) {
                Row() {
                  Text('使用帮助与快捷键').fontSize(15).fontColor(this.state.pal.TEXT).layoutWeight(1)
                    .textAlign(TextAlign.Start)
                  SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(14).fontColor([this.state.pal.TEXT_SUB])
                    .rotate({ angle: this.helpExpanded ? 180 : 0 })
                }.width('100%')
              }.width('100%').constraintSize({ minHeight: 64 }).padding(16)
                .backgroundColor(Color.Transparent).borderRadius(12).hoverEffect(HoverEffect.Highlight)
                .accessibilityText(this.helpExpanded ? '收起使用帮助与快捷键' : '展开使用帮助与快捷键')
                .onClick(() => { this.helpExpanded = !this.helpExpanded; })
            }
            .width('100%')
            .backgroundColor(this.state.pal.CONTENT)
            .borderRadius(12)
            .alignItems(HorizontalAlign.Start)
            if (this.helpExpanded) { this.helpContent() }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 32 })
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
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.state.pal.BG)
  }
  build() { Column() { SafePage() { this.pageContent() } }.width('100%').height('100%') }
}
