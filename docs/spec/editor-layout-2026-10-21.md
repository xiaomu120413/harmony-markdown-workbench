# 编辑页边栏布局修复 ST-LAYOUT-001

## PRD

- REQ-LAYOUT-001：行号和折叠箭头应并排，箭头与对应标题行对齐，不得堆叠到文档下方。
- REQ-LAYOUT-002：PC 文档侧栏背景应延伸到页面底部，状态栏只占正文区域；保留侧栏搜索、切换、置顶、删除和手机布局。
- REQ-LAYOUT-003：行号栏与正文使用相同底色，避免行号栏在状态栏上方结束时形成灰色台阶；保留行号、折叠与当前行提示。
- 范围：编辑页布局与 CodeMirror gutter 显示。非目标：右键菜单、文件内容、权限、保存流程和发布打包。

## RFC

引用 REQ-LAYOUT-001/002。修复前 gutterShown 强制 display:block，覆盖依赖源码 @codemirror/view 的 .cm-gutters display:flex，导致行号与折叠 gutter 纵向堆叠。现已改为 flex，隐藏行号仍沿用现有整组隐藏行为。

EditorScreen 原先把状态栏置于整个 EditorWorkspace 下方，再加页面底部 padding，侧栏因此提前结束。把 DocumentSidebar 提升到 EditorScreen 的下半区 Row，右侧 Column 包含工作区和原状态栏；底部不再增加外边距。侧栏及分隔线使用同一父容器高度。

风险：窄窗、分屏与加载失败状态需保持原有可用性。失败面板不展示侧栏。ArkUI 为布局职责，无新增业务 Service。回滚本次提交即可恢复。

2026-10-21 用户复查补充：REQ-LAYOUT-003。上一次修复消除了文档侧栏底部白条，但 CodeMirror 默认浅灰 gutter 在状态栏上方结束，依然构成小缺口。gutterShown 使用透明底色并移除其边线，与正文底色连续；不延长不可编辑区域或添加依赖字体/行号位数的固定宽度补丁。沿用 ST-LAYOUT-001，验收增加实际 bundle 明暗主题、行号切换和 PC 底部截图检查。

## Story

ST-LAYOUT-001，无新增权限和数据迁移依赖。

- 文件：EditorScreen.ets、EditorWorkspace.ets、web-tools/src/editor.js 及生成的 editor.bundle.js。
- 验收：MateBook Pro 检查箭头与标题同行、侧栏触底；切换编辑/预览/分屏、侧栏开关；现有宿主测试、源码/文档检查、Debug HAP 构建。
- 保留工作区已有右键菜单改动与其未跟踪文档，不纳入本次提交。

## 验证

环境：Windows / DevEco Studio 内置 JBR 与 SDK；2026-10-21，MateBook Pro HAD-W32，设备 3QC0124C11000711，API 26 / OpenHarmony 7.0.0.106。

- `node web-tools/build-web.js`：通过，重建离线 bundle。
- Chrome headless `--dump-dom --virtual-time-budget=2000` 加载实际离线 editor.bundle.js，调用 loadDocument 与 setLineNumbers。旧提交 bundle：行号矩形 `[0,0,20,485]`，折叠栏 `[0,485,20,485]`，alignment=false；修复 bundle：行号 `[0,0,20,485]`，折叠栏 `[20,0,10,485]`，alignment=true，隐藏与重新显示分别得到 none/flex。临时脚本与输出在忽略目录 `build-logs/layout-browser*.html`，不是伪造 DOM 的断言。
- `node scripts/test/test-host.cjs`：268/268；`node scripts/test/test-editor-actions.cjs`：40；`node scripts/test/test-window-viewport.cjs`：8，通过。宿主测试模拟平台边界，不代替真机。
- `hvigorw.bat assembleHap --mode module -p product=default -p buildMode=debug --no-daemon`：独立目录 `../local-sign/mumark-layout-debug-20261021` 构建，首次 34 个任务成功，合并保留当前右键菜单任务代码后的复验 33 个任务成功。使用已有签名配置，没有新增签名材料或改仓库签名配置。日志：`build-logs/layout-debug-build.log`、`layout-debug-final-build.log`。
- `install_app` 显式指定上述 MateBook 设备，复用签名覆盖安装成功；打开原有测试文档 matrix-20261021.md。截图确认折叠箭头位于第 1/2 行旁。UI 树侧栏矩形 `[98,296,456,1174]`，底端 y=1470，与窗口 `[76,76,2090,1394]` 底端一致；右侧状态栏 `[555,1421,1589,49]`，不占用侧栏底部。REQ-LAYOUT-001/002 通过。
- 预览模式可见 Web 为 preview.html，矩形 `[555,296,1589,1110]`；当前宽度开启侧栏时分屏按既有预算拒绝，收起侧栏后分屏两个 Web 分别 `[98,296,1023,1110]`、`[1122,296,1023,1110]`。再次切回编辑并展开侧栏正常。本次未输入、保存、删除或改动测试文档正文。
- 期间检测到其他任务同时修改 Web 平台菜单代码并覆盖安装，曾导致设备回到旧布局；本次最终验证包保留当时最新平台菜单代码。提交仅包含布局变更；EditorWorkspace 的重叠文件按 HEAD 生成仅移动侧栏的暂存版本，保留其他任务工作区差异。
- `node scripts/check/check-docs.mjs`、`check-source-encoding.mjs`、`check-source-size.mjs` 与 `git diff --check`：通过。

未验证：手机、实体平板、深色主题、窗口缩放、加载失败面板及长列表删除/置顶的逐项真机回归。未执行完整 SDK ohosTest 套件；本次使用上述宿主回归、实际浏览器几何对照和 PC 真机 UI 验收。未生成正式发布包。构建存在既有弃用 API 警告。本次仅修复布局，不能据此宣称全平台验收完成。

### 底部台阶补充验收

- `node web-tools/build-web.js`：通过。Chrome headless 加载实际 bundle，浅色 gutter 为透明且边线 0px；深色 gutter 与编辑器同为 rgb(30,30,30)，边线 0px；切回浅色仍透明。行号/折叠栏对齐、关闭与重新开启行号均通过。输出在 `build-logs/layout-notch-result.html`。
- 同一独立签名目录执行上述 Debug HAP 构建：33 个任务成功（19 executed / 14 up-to-date），日志 `build-logs/layout-notch-build.log`。保留当时最新的现有 WebDragStyle 右键菜单改动，但不纳入本次提交。
- MateBook 显式指定设备覆盖安装成功，打开 matrix-20261021.md，浅色真机截图 `C:/Users/mu/AppData/Local/Temp/mumark-bottom-flat.png` 确认行号栏灰色条消失、侧栏右边界一直到底，无原先状态栏上方的台阶；数字、折叠箭头与当前行高亮保留。REQ-LAYOUT-003 通过。
- `node scripts/test/test-editor-actions.cjs`：40 个场景通过；文档、UTF-8、源码行数与 `git diff --check` 通过。本次为纯样式补修，沿用上一轮其余回归证据，不重复执行完整 SDK ohosTest 或全平台验收；深色仅浏览器验证，未做深色真机切换。未改文档正文或生成正式包。

## 交付索引

| 提交 | 内容 | 验收结论 |
|---|---|---|
| `811d96a` | 恢复行号/折叠栏横向排列；文档侧栏延伸到页面底部 | REQ-LAYOUT-001/002：PC 验收通过 |
| `ad12e88` | 统一行号栏与正文底色，消除状态栏上方的灰色台阶 | REQ-LAYOUT-003：PC 验收通过 |

折叠按钮是既有功能，本轮仅修正其排列和底色，不新增折叠语义。操作说明见[使用说明](../user-guide.md#行号旁的折叠按钮)。本次整理只补齐说明与交付索引，不改变需求、设计或运行行为，因此不新增 PRD/RFC/Story。

整理验证：`node scripts/check/check-docs.mjs`、`node scripts/check/check-source-encoding.mjs` 与 `git diff --check` 通过。没有代码变更，不重复构建或运行设备测试；上述未验证项继续保留。
