@Entry
@Component
struct HomePage {
  @State private appVersion: string = 'V0.1';

  build() {
    Column({ space: 12 }) {
      Text('Harmony Markdown Workbench')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
      Text('工程基线 TASK-M0-01')
        .fontSize(14)
        .fontColor('#99000000')
      Text('首页功能（最近文件、固定文件、资料库、新建、打开外部文件）将在 M5-01 实现。')
        .fontSize(14)
        .fontColor('#99000000')
        .textAlign(TextAlign.Center)
      Text(`版本：${this.appVersion}`)
        .fontSize(12)
        .fontColor('#66000000')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }
}