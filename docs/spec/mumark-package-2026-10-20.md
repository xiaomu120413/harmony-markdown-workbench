# 正式包名与首发版本 ST-BRAND-002

2026-10-20，基线 fec4db1，工作区开始时干净。用户明确要求包名包含 MuMark，版本改为 1.0.0；显示名仍为木笺 MuMark。

REQ-BRAND-002：正式 bundleName 改为 com.mumark.app，versionName 为 1.0.0，versionCode 为 1000000。同步草稿版本元数据和本地签名脚本默认包名，明确证书/Profile 申请使用新包名。

设计与任务范围：ST-BRAND-002 只更新应用身份、草稿版本常量、签名脚本默认值与当前说明，不修改权限、SDK 下限、设备类型、界面、模块划分或业务格式，不增加封装。已有宿主机测试检查草稿版本与 AppScope 一致。历史验收包名保留以反映当时实际环境。

包名变化属于新的应用身份，不支持直接覆盖旧 com.markdownworkbench.app 或读取其沙箱。本轮不卸载或迁移旧安装；需要带走旧文档时先在旧应用中保存到用户目录或导出图文 ZIP。新证书/Profile 应绑定 com.mumark.app，包含获批的 FILE_ACCESS_PERSIST 权限；权限审核与正式证书由用户申请，本轮不声称签名获批。回滚可回退本提交，但两个包的沙箱仍互相隔离。

## 验证记录

- Windows / 当前 DevEco SDK / 内置 JBR：`node scripts/test/test-host.cjs` 255/255 通过，包含草稿 appVersion 与 AppScope versionName 的一致性验证。
- `hvigorw.bat test --mode module -p product=default`、`hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release` 均 BUILD SUCCESSFUL，日志在忽略目录 build-logs/mumark-package-test.log 与 mumark-package-release.log。既有 ArkTS 弃用/ESObject 等警告保留。
- Python zipfile 读取实际 Release unsigned HAP 的 module.json：bundleName=com.mumark.app、versionName=1.0.0、versionCode=1000000、vendor=MuMark，断言全部通过；最低与目标 API 仍为 22（打包值 60002022）。
- Git Bash `bash -n scripts/build/sign-local.sh` 通过；源码行数、严格 UTF-8、文档链接与 `git diff --check` 通过，手写文件仍不超过 500 行。

未进行新正式包装机、正式签名或旧数据迁移验收：本轮产物为 unsigned HAP，新包对应的正式证书/Profile 待用户申请；没有复用旧包身份或卸载旧应用。

## 1.0.1 版本更新 ST-BRAND-003（2026-10-22）

REQ-BRAND-003：用户要求版本更新到 1.0.1。同步 AppScope versionName 与 DraftStore 的草稿版本标记，versionCode 从 1000000 递增到 1000001，README 当前版本同步。包名、最低 API 24、签名与数据目录不变；历史验收资料保留当时版本。本次不安装设备、不重新签正式包；回滚可回退本提交。

验证：`node scripts/test/test-host.cjs` 268/268 通过（平台 IO mocked，含草稿版本一致性）；文档、UTF-8、500 行检查及 `git diff --check` 通过。`hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release --no-daemon` BUILD SUCCESSFUL，33 项任务，日志 `build-logs/version101-release.log`。读取实际 unsigned HAP 的 module.json 确认 com.mumark.app / 1.0.1 / 1000001，最低与目标 API 均为 60101024。仓库未配置签名，构建明确跳过签名，本次产物不作为可安装的正式签名包交付。

### 正式 Release 重新打包 ST-BRAND-004

用户随后要求重新打包 Release。从 c965093 建立仓库外独立源码副本 `C:/Users/mu/Desktop/code/local-sign/mumark-release-c965093-standard`，复用既有 release signingConfig、Mumark.cer 和 MumarkRelease.p7b，不创建证书，不修改主仓库签名配置。AppScope 与 entry/src/main 已跟踪文件按换行归一化逐一核对，与当前源码一致。

`hvigorw.bat assembleApp --mode project -p product=default -p buildMode=release --no-daemon`：44 项任务，BUILD SUCCESSFUL，日志 `build-logs/version101-standard-release.log`。官方标准构建生成的 signed APP 与独立 signed HAP 分别经 `hap-sign-tool.jar verify-app` 验证成功；提取的签名证书指纹与 Mumark.cer 一致，提取的 Profile SHA-256 与原正式 MumarkRelease.p7b 一致。APP 内嵌 entry-default.hap 是构建工具生成的无独立 HAP 签名块载荷，不将它当作独立安装包；签名验证结论针对 APP 本体及另行交付的 signed HAP。

独立 HAP 与 APP 内嵌模块均核对：com.mumark.app、1.0.1、versionCode 1000001、最低/目标 API 60101024，唯一申请权限为 FILE_ACCESS_PERSIST。产物仅保留忽略目录 dist，不入库，不安装或改动设备文档。本次不重复运行源码未变化的业务测试；沿用上述 268 项测试，提交前文档检查与 `git diff --check` 通过。

| 本地产物 | SHA-256 |
|---|---|
| `dist/mumark-1.0.1-release-signed.app`（上架包） | `6E3BB94E1BF741F359A3C0C747FF74C9054F0905386BCB89188A466A7B95E623` |
| `dist/mumark-1.0.1-release-signed.hap`（独立签名包） | `73E9104211C449D8687929E4E6625B98914DC3E43D4493895B7091492AA0AF02` |
