# Clarify 阶段假设与默认值

依 SDD 11.3：仅澄清会改变架构或验收的问题；未获答复时使用以下默认值，并持续更新本文件。若某假设被推翻，先更新对应 ADR 再改实现。

## A-01 目标 SDK 与最低版本

- **默认值**：targetSdkVersion = `6.0.2(22)`，compatibleSdkVersion = `6.0.2(22)`（HarmonyOS 6.0.2 / API 22），runtimeOS = HarmonyOS。
- 本机构建环境 SDK：`ets` API 26（HarmonyOS 6.6.0 Beta1，`oh-uni-package.json` 26.0.0.23）。
- 依据：同目录可构建工程 `PythonExecDemo` 使用完全相同的版本组合并成功产出 unsigned HAP。
- 风险：API 22 目标 + API 26 SDK 的组合已在 M0-01 构建验证通过；后续若需覆盖 HarmonyOS 5.x 设备，下调 compatibleSdkVersion 并回归（ADR-006）。
- 待澄清：正式发布目标设备系统版本范围。

## A-02 bundleName 与 vendor

- **默认值**：`com.markdownworkbench.app`，vendor `HMWB`，versionCode 1000000，versionName 1.0.0。
- 上架前如需变更 bundleName，仅修改 `AppScope/app.json5` 及相关签名配置，不影响构建。

## A-03 设备类型声明

- **默认值**：`deviceTypes = ["phone", "tablet"]`。PC/2in1 为 V0.2 工作区目标，M0-01 不声明（避免 2in1 窗口约束影响早期验证）；M6-01 响应式任务时补全。

## A-04 签名策略

- 工程不配置 `signingConfigs`，调试构建产出 unsigned HAP；真机安装调试通过 DevEco Studio 自动签名（本地 `.p12/.cer` 不入库）。正式发布签名于 M6-04 配置。

## A-05 CI 策略

- GitHub-hosted runner 无 HarmonyOS SDK；CI 采用**自托管 runner + clean-build 脚本**模式，本地以 `scripts/clean-build.sh` 作为"无缓存环境"等价验证。workflow 未实跑通过前不作为门禁（R-06）。

## A-06 日志与隐私

- 日志标识 `HMWB`，domain 0x0000；不打印文件路径、URI、正文与用户名信息（SDD 6.3）。
- V0.1 不申请 INTERNET 权限（远程图片需求须 ADR 批准）。

## A-07 工程模型版本

- modelVersion `6.0.1`（与 hvigor 6.26.1、现有工程一致），wrapper 以转发方式调用 DevEco 官方 `tools/hvigor/bin/hvigorw.js`（ADR-006 说明原因）。

## A-08 签名与真机调试策略（M0-02 实测，2026-08-29）

- 工程保持 `signingConfigs` 为空（密码零入库）；`scripts/sign-local.sh` 产出官方 OpenHarmony CA 签名安装包（材料在工程外 `../local-sign/`，不入库）。
- **真机安装已验证**（MateBook Pro / OpenHarmony 7.0.0.28）：官方 CA 体系 + 设备信任库补入 Profile CA（一次性操作，见 external-uri.md 第 5 节）。
- module.json5 `deliveryWithInstall=false`（true 会被动态交付机制回收）。
- **外部 URI 为单次运行临时授权**（重启实测失效 13900001）：V0.1 产品明示"临时访问"，最近文件提供"重新定位"（ADR-009 草案）。

## 待澄清问题（不阻塞当前任务）

1. 正式发布的 HarmonyOS 系统版本下限？
2. 是否已有 AppGallery 开发者账号/证书计划（影响 A-02/A-04）？
3. PC/2in1 是否需要在 V0.1 真机验收（影响 A-03）？