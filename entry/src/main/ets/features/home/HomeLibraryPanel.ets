import { ControlStyle, ControlMetrics } from '../../common/ControlStyle';
import { HomeState } from './HomeState';
import { HomeController } from './HomeController';

@Component
export struct HomeLibraryPanel {
  @ObjectLink state: HomeState;
  @Require actions: HomeController;
  @Builder
  libraryPanel() {
    Column({ space: 6 }) {
      Row() {
        Text(`我的文档 · ${this.state.libraryFiles.length} 个`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.state.pal.TEXT)
          .layoutWeight(1)
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(20).fontColor([this.state.pal.TEXT])
        }
          .attributeModifier(new ControlStyle(this.state.pal, 'quiet', true)).accessibilityText('关闭')
          .onClick(() => { this.state.pickingFile = false; })
      }
      .width('100%')

      if (this.state.libraryFiles.length === 0) {
        Text('还没有保存过文档')
          .fontSize(13)
          .fontColor(this.state.pal.TEXT_FAINT)
          .padding(8)
      }
      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.state.libraryFiles, (name: string) => {
            if (this.state.renamingFrom === name) {
              Row({ space: 8 }) {
                TextInput({ text: this.state.renameText })
                  .fontSize(14)
                  .height(ControlMetrics.HEIGHT)
                  .padding({ left: 8, right: 8 })
                  .backgroundColor(this.state.pal.CONTENT)
                  .borderRadius(8)
                  .layoutWeight(1)
                  .onChange((v: string) => {
                    this.state.renameText = v;
                  })
                  .onSubmit(() => this.actions.confirmRename())
                Button({ type: ButtonType.Normal }) {
                  SymbolGlyph($r('sys.symbol.checkmark')).fontSize(20).fontColor([this.state.pal.TEXT])
                }
                  .attributeModifier(new ControlStyle(this.state.pal, 'quiet', true)).accessibilityText('确认')
                  .onClick(() => this.actions.confirmRename())
                Button({ type: ButtonType.Normal }) {
                  SymbolGlyph($r('sys.symbol.xmark')).fontSize(20).fontColor([this.state.pal.TEXT])
                }
                  .attributeModifier(new ControlStyle(this.state.pal, 'quiet', true)).accessibilityText('关闭')
                  .onClick(() => {
                    this.state.renamingFrom = '';
                  })
              }
              .width('100%')
              .padding({ top: 3, bottom: 3 })
            } else {
              Row({ space: 10 }) {
                Text(name)
                  .fontSize(14)
                  .fontColor(this.state.pal.TEXT)
                  .maxLines(1)
                  .layoutWeight(1)
                Button({ type: ButtonType.Normal }) {
                  SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(20).fontColor([this.state.pal.TEXT])
                }
                  .attributeModifier(new ControlStyle(this.state.pal, 'quiet', true)).accessibilityText('更多操作')
                  .onClick(() => this.actions.libraryRowMenu(name))
              }
              .width('100%')
              .height(ControlMetrics.HEIGHT)
              .padding({ left: 12, right: 12 })
              .onClick(() => {
                this.state.pickingFile = false;
                // listLibrary 返回裸文件名，路由需要完整相对路径（修复 loadFailed 误报）
                this.actions.goEditorWith(`library/${name}`);
              })
            }
          }, (name: string) => name + (this.state.renamingFrom === name ? ':edit' : ''))
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 200 })
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.state.pal.CONTENT)
    .borderRadius(12)
  }
  build() { this.libraryPanel() }
}
