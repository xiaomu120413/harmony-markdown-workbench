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

本轮未执行设备安装与 SDK 设备测试套件，没有重新宣称手机、平板或右键真机回归通过；此前原生菜单实测见同目录 right-click-menu-2026-10-21.md。dist 内此前正式包仍为旧 API 22 基线，本轮未重签或替换，不应将其当作本次 API 24 构建交付。
