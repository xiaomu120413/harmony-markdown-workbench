# ADR-007：bundleName 与设备类型默认值

- 状态：接受（默认值，可变更）。第 2 条的 PC/2in1 延期项已于 2026-10-10 闭环（见下）。
- 背景：M0-01 需要确定 bundle 与设备声明；无既有公司域名可依。
- 决策：
  1. bundleName = `com.markdownworkbench.app`，vendor = `HMWB`，versionCode 1000000 / versionName 1.0.0。上架前如需变更，仅涉及 `AppScope/app.json5` 与签名配置。
  2. `deviceTypes = ["phone", "tablet"]`；PC/2in1 在 M6-01 响应式任务补全（V0.2 工作区能力，SDD 3.2/4.2），避免提前引入 2in1 窗口约束。
- 后果：2in1 设备在 V0.1 前期不参与真机验收矩阵。
- 关联：A-02、A-03；SDD 4.2。
- **2026-10-10 更新（V0.2 三端总装）**：`deviceTypes` 补 `"2in1"`（对齐同设备 Wireshark HAP 的实证声明），
  真机 HAD-W32（MateBook Pro，OpenHarmony 7.0.0.106）安装运行通过；三端断点
  （phone <600vp / tablet 600–959vp / pc ≥960vp，DPR 1.9）逐档真机验证见 acceptance.md V0.2 节。