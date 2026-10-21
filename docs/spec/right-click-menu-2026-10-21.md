# 原生右键菜单 ST-MENU-001

## 需求与范围

REQ-MENU-001：编辑区鼠标、触控板右键可以打开系统菜单；保留长按菜单及图片粘贴，不新增剪贴板读取权限。用户已确认使用系统原生竖排右键菜单，长按继续使用系统横向菜单。

## 设计

当前 SDK 的 ets/component/web.d.ts 将 enableDefaultContextMenu 标为 API 24，默认值为 false。原代码未启用该开关，导致鼠标右键没有默认菜单。

在已有 WebDragStyle 中按 deviceInfo.sdkApiVersion >= 24 启用该属性，编辑器与两种预览共用现有 modifier。不引入自定义菜单、菜单状态或剪贴板读取接口。API 22、23 不调用新接口，继续使用长按或键盘快捷键。既有 API 26 拖动开关保持原逻辑。

ST-MENU-001 仅修改 WebDragStyle 与对应宿主机测试。回退时删除菜单开关及其测试即可。平台菜单的外观和安全 PasteButton 由系统管理。

## 验证（2026-10-21）

- Windows / 当前 DevEco SDK：node scripts/test/test-host.cjs，268/268 通过；覆盖 SDK 22–26 的菜单开关边界及 API 26 拖动控制。平台能力以 mock 验证，不能代替旧系统实机测试。
- node scripts/test/test-clipboard-image.cjs 通过，覆盖真实 Web 粘贴处理、存储和交付模块，系统事件边界使用 mock。
- node scripts/test/test-editor-actions.cjs：40 场景通过；node scripts/test/test-file-transactions.cjs：35 场景通过。
- MateBook Pro / API 26：复现修复前右键不显示菜单；启用后用 hdc shell uinput -M ... -c 1 发送右键，UI 树出现系统竖排复制、PasteButton 粘贴、剪切、全选。使用本任务的 matrix-20261021.md 测试文档执行全选、剪切、粘贴；正文先变空再恢复原有标题和两条图片引用，未操作用户原有文档。
- 同设备 hdc shell uitest uiInput longClick 1300 650：仍出现横向系统 PasteButton 和全选按钮。
- 没有增加 READ_PASTEBOARD，也没有调用主动读取剪贴板的接口。

未验证：实体触控板手势、API 22/23 旧系统实机右键及本次菜单内图片粘贴。输入注入验证的是鼠标右键事件路径；不能报告为实体触控板验收。旧系统原生竖排右键菜单不在平台支持范围内。

最终源码验收：基于 ad12e88 与本次 modifier 补丁创建独立构建目录，assembleHap --mode module -p product=default -p buildMode=release --no-daemon 成功（34 tasks）；使用既有调试签名覆盖安装至 MateBook，未卸载应用，原最近文档仍在，打开 matrix 测试文档后再次确认系统竖排菜单。日志为本地忽略目录 build-logs/right-menu-final-debug-build.log。根工程现有签名配置未改动，也未申请新证书。

静态门禁：node scripts/check/check-docs.mjs（65 Markdown）、check-source-encoding.mjs（244 文件）、check-source-size.mjs（130 手写文件）及 git diff --check 通过，手写文件均不超过 500 行。SDK 设备测试套件未执行，本次以宿主机测试与上述 API 26 实机检查为证据。

正式交付：源码 f459380 用既有 release 配置执行 assembleApp --mode project -p product=default -p buildMode=release --no-daemon，44 tasks 成功。hap-sign-tool.jar verify-app 返回 Digest verify result: true 与 verify-app success；提取的 Profile 与原 MumarkRelease.p7b 的 SHA-256 一致。正式包输出至 dist/mumark-1.0.0-release-signed.app（SHA-256：3BA81555AFAABC8BC0282EC4E80993A1B5D2A0C11368349678B66ABC07677381）及 dist/mumark-1.0.0-latest-release-signed.hap。正式 app_gallery 包未替代设备上的既有调试签名包；没有卸载或清空文档。
