# 正式包名与首发版本 ST-BRAND-002

2026-10-20，基线 fec4db1，工作区开始时干净。用户明确要求包名包含 MuMark，版本改为 1.0.0；显示名仍为木笺 MuMark。

REQ-BRAND-002：正式 bundleName 改为 com.mumark.app，versionName 为 1.0.0，versionCode 为 1000000。同步草稿版本元数据和本地签名脚本默认包名，明确证书/Profile 申请使用新包名。

设计与任务范围：ST-BRAND-002 只更新应用身份、草稿版本常量、签名脚本默认值与当前说明，不修改权限、SDK 下限、设备类型、界面、模块划分或业务格式，不增加封装。已有宿主机测试检查草稿版本与 AppScope 一致。历史验收包名保留以反映当时实际环境。

包名变化属于新的应用身份，不支持直接覆盖旧 com.markdownworkbench.app 或读取其沙箱。本轮不卸载或迁移旧安装；需要带走旧文档时先在旧应用中保存到用户目录或导出图文 ZIP。新证书/Profile 应绑定 com.mumark.app，包含获批的 FILE_ACCESS_PERSIST 权限；权限审核与正式证书由用户申请，本轮不声称签名获批。回滚可回退本提交，但两个包的沙箱仍互相隔离。

## 验证记录

- Windows / 当前 DevEco SDK / 内置 JBR：`node scripts/test-host.cjs` 255/255 通过，包含草稿 appVersion 与 AppScope versionName 的一致性验证。
- `hvigorw.bat test --mode module -p product=default`、`hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release` 均 BUILD SUCCESSFUL，日志在忽略目录 build-logs/mumark-package-test.log 与 mumark-package-release.log。既有 ArkTS 弃用/ESObject 等警告保留。
- Python zipfile 读取实际 Release unsigned HAP 的 module.json：bundleName=com.mumark.app、versionName=1.0.0、versionCode=1000000、vendor=MuMark，断言全部通过；最低与目标 API 仍为 22（打包值 60002022）。
- Git Bash `bash -n scripts/sign-local.sh` 通过；源码行数、严格 UTF-8、文档链接与 `git diff --check` 通过，手写文件仍不超过 500 行。

未进行新正式包装机、正式签名或旧数据迁移验收：本轮产物为 unsigned HAP，新包对应的正式证书/Profile 待用户申请；没有复用旧包身份或卸载旧应用。
