import { router } from '@kit.ArkUI';

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
      // 临时入口：M0-02 尖峰验证页（M5-01 实现正式首页时移除）
      Button('M0-02 尖峰：外部文件 URI')
        .fontSize(14)
        .margin({ top: 16 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/SpikeUriPage' });
        })
      // 临时入口：M0-03 尖峰验证页（M2 正式编辑器页替换）
      Button('M0-03 尖峰：编辑器')
        .fontSize(14)
        .margin({ top: 8 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/SpikeEditorPage' });
        })
      // 临时入口：M0-04 尖峰验证页（M4 正式实现替换）
      Button('M0-04 尖峰：保存恢复')
        .fontSize(14)
        .margin({ top: 8 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/SpikeSavePage' });
        })
      // 临时入口：M1-01 适配器契约验证页（M1 验收）
      Button('M1-01 尖峰：适配器契约')
        .fontSize(14)
        .margin({ top: 8 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/SpikeContractPage' });
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }
}