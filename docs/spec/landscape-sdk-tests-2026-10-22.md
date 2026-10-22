# 手机横屏与 SDK 单测补验 ST-QUALITY-003

REQ-QUALITY-003：完成 API 24 手机模拟器横屏的编辑、查找、软键盘、菜单、保存与预览回归；排查 SDK 单测 LocalSocket 错误，区分编译、用例、运行器通信与报告失败，不能以 BUILD SUCCESSFUL 代替断言通过。更新现有 Markdown/DOCX 自测报告并提交推送。

设计与边界：优先使用 SDK Emulator 官方旋转命令，不修改设备分辨率伪装横屏；只操作本任务测试文件，不卸载或清数据。排查现有 hvigor 测试链路、依赖及 SDK 原始输出；不修改 SDK 安装文件、不屏蔽未知错误、不建立产品通用封装。必要修复只进入实际失败的布局或测试交付路径，手写文件不超过 500 行；回退不改变文档格式、权限或签名。

验证：核对真实窗口尺寸和方向、键盘前后布局及文件内容，核对 SDK 测试结果计数与当前时间、失败情况、原始日志和覆盖率产物。记录官方工具参数及未解决项，DOCX 渲染检查后提交推送。

排查确认：原 EntryAbility 未声明 orientation。官方窗口旋转文档说明 unspecified 在直板手机通常保持竖屏，不支持传感器旋转；增加 auto_rotation_restricted，允许传感器旋转并尊重系统旋转锁定，不强制方向或改屏幕尺寸。

SDK 新鲜缓存重跑已产生 205/205 通过结果及覆盖率报告；LocalSocket 来自 SDK coverage 插件向 Previewer 传入固定的 IDE 管道名，CLI 未创建对应管道。继续验证日志门禁，防止沿用旧结果或把用例失败当成功。

## 验证结果

2026-10-22，Pura 90 API 24 模拟器，Emulator 26.0.0.400。复用原调试签名覆盖安装，无卸载、清数据或新增权限。

- 修正入口方向为 auto_rotation_restricted；官方 Emulator left/right 旋转命令后，list_windows 实测 1320×2856 ↔ 2856×1320，两个横屏方向均覆盖。开启系统旋转锁定后再次转向仍保持竖屏，最后回到正向竖屏。
- 原 compactHeight 条件无论是否有键盘都隐藏工具栏，导致横屏预览和命令入口消失。Header/CommandBar 复用既有 keyboardVisible，只在低矮且键盘出现时收起；未增加通用适配层。四组菜单、预览、长工具栏水平滚动可用，长菜单项可纵向滚动。
- 查找面板低矮窗口限高从 116vp 调整到 60vp，键盘打开时正文仍有 81px 可见，中文查找“保存”得到 1/2 命中；Escape 关闭、Back 收键盘后工具栏恢复，正文编辑键盘场景高度 319px。测试文档临时输入并保存为 110 字节，撤销保存后恢复 89 字节，SHA-256 与原样本一致。没有删除用户文档。
- SDK 恢复依赖使用 `ohpm install --all --no-experimental-concurrently-safe`；Windows 并发安装产生的空包目录已恢复，本地 clean-build 使用相同参数。SDK 报旧缓存 scopeNames 冲突后，已先核对绝对路径在本仓库内，再把 entry/.test 备份移至 build-logs/quality23-test-before，重新生成测试产物。
- `hvigorw.bat test --mode module -p product=default --no-daemon`：20 tasks 成功；独立结果门禁核对 205 个用例逐例 Success，Failure/Error/Ignore 均为 0；行覆盖率 824/1017（81.02%）、函数 104/147（70.75%）、分支 280/365（76.71%）。只代表 SDK 统计模块，非全应用覆盖率。
- 新增单一脚本 `check-sdk-results.mjs`，检查开始时间、编译成功、三份当前产物的新鲜度、逐例数量/结果、引擎完成标记和覆盖率。已在隔离的缓存副本上验证：正常样本放行，失败用例、缺失摘要、零用例、过期样本、编译失败均拒绝。CI 与两种 clean-build 已接入，不再只看任务退出码或 BUILD SUCCESSFUL。
- SDK 原始 LocalSocket 和 trace 管道诊断仍保留在 coverage.log；已确认本轮没有阻断断言与覆盖率生成。不改 SDK、不伪造管道、不声称诊断已消失，修正上一版报告的“SDK 单测被阻断”结论。
- 11 组宿主回归通过；手写文件 ≤500 行、UTF-8、本地 Markdown 链接与 diff 检查通过。签名 HAP 33 tasks、原正式签名 APP 42 tasks 构建成功；正式 APP/HAP verify-app、Profile 哈希与 API 24/旋转元数据核对通过，哈希见更新后的自测报告。

证据：本地 build-logs/quality23-* 包括新测试时间戳、构建日志、SDK 原始日志/结果/覆盖率、横屏截图与 110/89 字节落盘样本。Markdown/DOCX 报告已更新；DOCX 交付前渲染逐页检查。Linux 自托管 CI 未实际调度运行，云测、实体外设及 L1/L2 正式认证不在本次完成范围。

依据：[官方窗口旋转说明](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/window-rotation)；本机 SDK coverage 插件 previewer.js 的 getSpawnChild 固定传入 `-s phone_1702972840143_1`、`-ts trace_7947_commandPipe`，用于判断诊断来源，文件未改动。
