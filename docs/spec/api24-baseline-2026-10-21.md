# API 24 基线 ST-SDK-001

REQ-SDK-001：按用户确认，将木笺最低 API 要求提升为 24，整理相关代码与当前文档并提交。

设计：compatibleSdkVersion 与 targetSdkVersion 同步改为 6.1.1(24)，避免目标版本低于最低版本；版本字符串依据本机 SDK 的 hms/ets/build-tools/ts-checker-hooks/sdkApiVersionMap.json。包名、应用版本、签名及存储格式不变。已有 Web modifier 直接启用 API 24 默认右键菜单，删除失效的 API 22/23 菜单降级分支及测试；API 26 拖动能力仍须门控。没有新增封装或权限。

范围：工程配置、WebDragStyle、对应宿主机测试、README/假设/ADR 与本记录。历史 API 22 设备验收和截图描述保持原样，不能改写成 API 24 的验收证据；之前右键菜单记录的旧系统策略由本决策取代。

安装边界：API 22、23 设备无法安装新包，已有安装与用户文档不主动清除。回退需恢复 API 22 配置及菜单版本判断，重新构建并验证，不涉及数据迁移。

验证（2026-10-21，Windows / DevEco 当前 API 26 SDK）：

- `node scripts/test/test-host.cjs`：268/268 通过，覆盖 API 24、25、26 的默认菜单及 API 26 拖动判断；平台接口使用 mock。
- `hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release --no-daemon`：33 tasks 成功；根工程没有签名配置，按原设置产出 unsigned HAP，未修改签名材料。日志在本地 build-logs/api24-baseline-build.log。
- 用 Python zipfile/json 检查产物 module.json：minAPIVersion 与 targetAPIVersion 均为 60101024（6.1.1 API 24 的打包值），包名 com.mumark.app、版本 1.0.0 保持一致。初次以裸 API 数字 24 比较断言失败，改按实际版本编码核对后通过。
- 文档检查 66 Markdown、严格 UTF-8 检查 245 文件、500 行检查 130 手写文件，以及 `git diff --check` 通过。

本轮未执行设备安装与 SDK 设备测试套件，没有重新宣称手机、平板或右键真机回归通过；此前原生菜单实测见同目录 right-click-menu-2026-10-21.md。

## 正式签名交付（2026-10-21）

用户要求重新签发 API 24 release 包。源码基线 c796a83；独立构建目录只复用此前正式 signingConfigs 和产品 signingConfig，不复制旧 SDK 版本字段。未新建证书或 Profile，未改根工程签名配置。

- `assembleApp --mode project -p product=default -p buildMode=release --no-daemon`：44 tasks 成功，包含 SignApp；日志 build-logs/api24-formal-release.log。
- `hap-sign-tool.jar verify-app` 分别验证正式 APP 和 HAP：均返回 Digest verify result: true 与 verify-app success。提取的两份 Profile 均与原 sign_tools/MumarkRelease.p7b 的 SHA-256 一致。HAP 验证初次使用不存在的 verify 子命令失败，依据工具帮助改为 verify-app 后通过。
- 检查已签名 APP 内嵌 HAP 和独立签名 HAP 的 module.json：minAPIVersion/targetAPIVersion 均为 60101024；com.mumark.app、1.0.0、versionCode 1000000 保持一致。
- 已替换 dist/mumark-1.0.0-release-signed.app，SHA-256：BF5FE3F29C1B5BF90200C9F6EF020E2EC39368826355B0E39E65964F46697C01。
- 已替换 dist/mumark-1.0.0-latest-release-signed.hap，SHA-256：B3EAAB26FF83665ACA28D30CB8C56DE382E011FBE016D47D39AB04F9D0F3B93F。

产物及签名材料不入库；本次验签和元数据检查通过，不代表正式应用市场安装验收。
