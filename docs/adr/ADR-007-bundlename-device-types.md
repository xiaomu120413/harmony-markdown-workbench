# ADR-007：bundleName 与设备类型默认值

- 状态：接受（默认值，可变更）。
- 背景：M0-01 需要确定 bundle 与设备声明；无既有公司域名可依。
- 决策：
  1. bundleName = `com.markdownworkbench.app`，vendor = `HMWB`，versionCode 1000000 / versionName 1.0.0。上架前如需变更，仅涉及 `AppScope/app.json5` 与签名配置。
  2. `deviceTypes = ["phone", "tablet"]`；PC/2in1 在 M6-01 响应式任务补全（V0.2 工作区能力，SDD 3.2/4.2），避免提前引入 2in1 窗口约束。
- 后果：2in1 设备在 V0.1 前期不参与真机验收矩阵。
- 关联：A-02、A-03；SDD 4.2。