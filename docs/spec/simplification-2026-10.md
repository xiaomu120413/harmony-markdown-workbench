# 重复代码精简 ST-SIMPLIFY-001

REQ-SIMPLIFY-001：删除没有独立规则的回调适配、运行时转发、队列容器和重复偏好存储；不新增架构层、状态或依赖，手写文件不超过 500 行。

参考木枢 RdpClientController / WindowsConnectionStore 与 MuTransfer AppearanceViewModel：有实际状态编排或平台适配职责的边界保留，不机械复制两者的层次。

本轮范围：EditorRuntime 的方法并回现有 EditorController；EditorPageDeps 删除，三处保存协调器初始化复用 Controller 内的同一个普通方法；EditorBridgeChannel 的两个运行字段并入现有 EditorEnvironment；WorkspaceUiStore 的侧栏偏好并入使用相同 hmwb_metadata 的 MetadataStore，保留原键和失败回退；OutlineEntry 并入 EditorState，删除未使用的 RouteParams 和 EditorTypes 文件。

保留文件校验、UTF-8/BOM/换行、安全解析、草稿、冲突、单文件持久授权、过期回调与快照版本检查。测试专用领域契约不因没有页面直接引用而删除。

验证：真实业务模块的主机回归、回调绑定与新文档/另存版本隔离、侧栏偏好兼容/失败回退，以及 ArkTS 编译、Release HAP、UTF-8/文档/500 行检查。若有设备可用，仅升级验证包做必要交互回归，不清除生产数据。

回滚：整体回退本次提交，偏好键与文档格式不变。

## 验证记录

2026-10-19，Windows / DevEco JBR / API 26 SDK，最低兼容 API 22。初始工作区干净。参考仓库仅阅读，没有修改。

- 删除 5 个实现文件，生产源码净减少 107 行；Controller 为 212 行，MetadataStore 为 78 行。没有增加类、接口、观察字段或依赖。
- draftIdOf 与 fingerprintOf 原实现完全相同，统一使用 draftIdOf；大纲的范围类型保留，只有未使用的路由类型删除。
- SaveCoordinatorDeps 使用现有回调接口的函数属性形式，符合 ArkTS 对有类型对象字面量的要求。三个初始化位置共用相同回调绑定，加载/另存时的 session/version 设置原样保留。
- `node scripts/test/test-host.cjs`：237/237，通过原领域/文件回归及旧侧栏键、最近索引不被覆盖、偏好失败回退测试。
- `node scripts/test/test-editor-actions.cjs`：24 组，通过每次挂载的队列隔离、退出后不接收旧事件、查找/加载过期回包，以及严格 Web 读取失败与可降级返回值的区分。
- `node scripts/test/test-file-transactions.cjs`：14 组，通过另存目标切换和继续保存、导出不换目标、取消/失败保留原会话、旧选择器回调丢弃。
- `test-page-viewmodels.cjs`、`test-external-access.cjs`、`test-window-viewport.cjs`：7、9、8 组通过。上述平台边界均为 mock。
- `hvigorw.bat test --mode module -p product=default`、`hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release`：BUILD SUCCESSFUL，日志 `build-logs/simplify-test.log`、`build-logs/simplify-release.log`；既有 ESObject/弃用警告保留。
- `check-source-size.mjs`、`check-source-encoding.mjs`、`check-docs.mjs`、`git diff --check`：通过；122 个手写源文件/测试/脚本均不超过 500 行，中文回读正常。

### 平板实测

PCE-W30 / MatePad Pro，OpenHarmony 6.0.2.130、API 22、2880×1920。只升级 `com.markdownworkbench.validation`，未清数据、未覆盖生产安装。

- 打开本任务此前创建的外部测试文档，58 字符正常加载；追加 Slim1649、保存并重新进入，67 字符保留。分屏正文与预览一致。
- 折叠侧栏后返回首页，再打开文档仍为折叠；随后恢复原先的展开偏好。合并 Store 后旧偏好键正常生效。
- 另存为 `MuMark-Slim-1703.md` 后标题切换为新文件；追加 SaveNew 并保存。升级最终验证包、重新启动，从最近列表直接打开新文件，75 字符及新增标记保留，无需重新选文件。[复读截图](../ux/simplification/reopened.jpg)。
- 一次坐标输入误落到本任务的测试正文，已恢复并回读；最终文件名通过原生控件句柄输入、工具精确验证后才保存，未把输入派发视为通过。
- 截图源：本机 `harmonyos-screenshots/screenshot_20261019_170518.jpeg`，2880×1920，仅等比缩小至 1200×800。

未验证：真实手机、2in1、物理设备重启、不同云盘提供方及全套导出字节检查。本轮没有改动这些实现，相关取消/失败/导出路径仅补充主机回归，不声称重新完成全部设备验收。
