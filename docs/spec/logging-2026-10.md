# 日志统一 ST-LOG-001

REQ-LOG-001：业务与平台适配代码不再直接调用 hilog，统一域、级别与消息输出，不新增运行状态或继承关系。

依据：木枢 `demo/harmony/app/common/src/main/ets/rdp/RdpLogger.ets` 使用静态 debug/info/warn/error 方法和私有消息占位符；MuTransfer 当前 Ability 主要直接使用 console.error，没有同类统一封装。木笺采用木枢的模式，只增加一个 9 行 MuLogger。

统一调用 MuLogger.info/warn/error，域为 0、tag 为 MuMark、消息格式为 `%{private}s`。删除各处 DOMAIN/TAG、note/append 转发，不要求业务类继承，不创建模块日志实例、工厂或接口。消息中的百分号按原文输出，授权失败继续只记录错误代码。调试过滤命令改用 `hilog -x -T MuMark`；旧验收日志的历史标签保持原记录。

验证：既有业务/文件/权限/视口回归，日志级别/tag/字面量测试，ArkTS 测试和 HAP 构建，以及 UTF-8、文档与 500 行检查。仅整理日志，不修改业务行为与权限；不要求重新执行完整文件真机交互。

回滚：回退本次提交。

2026-10-19，Windows / DevEco JBR / API 26 SDK：

- `node scripts/test-host.cjs`：235/235，通过新增的四级日志、固定 tag、私有格式和字面量测试。
- `test-editor-actions.cjs`、`test-file-transactions.cjs`、`test-page-viewmodels.cjs`、`test-external-access.cjs`、`test-window-viewport.cjs`：分别 23、14、7、9、8 组通过，平台边界为 mock。
- `hvigorw.bat test --mode module -p product=default`、Release `assembleHap`：BUILD SUCCESSFUL，日志 `build-logs/logger-test.log`、`build-logs/logger-release.log`，既有弃用/ESObject 警告保留。
- `check-source-size.mjs`、`check-source-encoding.mjs`、`check-docs.mjs`、`git diff --check`：通过；127 个手写源文件/测试/脚本均不超过 500 行，中文回读正常。
- 生产源码含 MuLogger 净减少 15 行；只有 MuLogger 导入 hilog，无额外继承、日志实例或业务状态。未重新装机回归，未改动参考仓库。
