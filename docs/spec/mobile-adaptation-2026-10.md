# 手机、平板安全区与编辑器拆分

2026-10-19，TASK-MOBILE-001，基线 c8d50e3。

## 需求

- FR-MOBILE-001：手机和平板内容避让状态栏、刘海、底部导航与横屏侧边区域；窗口变化和旋转后更新；桌面三键仍可操作，不叠加重复留白。
- FR-MOBILE-002：软键盘采用页面缩放避让，编辑区保持可见；紧凑高度下减少辅助栏，查找/重命名/设置可滚动；不手动再加一份键盘高度。
- FR-MOBILE-003：切换断点不重建文档会话、不丢正文；延续保存、恢复、授权、拖入与交付的回归。
- FR-MOBILE-004：手写应用源码文件不超过 500 行；按状态、会话、编辑命令、预览、持久化、交付和视图职责拆分，增加门禁；不靠继承链或机械片段拼接规避限制。
- FR-MOBILE-005：可用设备实际验收，记录真实设备类型、系统和未验证项；提交并推送。

## 设计与参考

MuTransfer 位于相邻 ftp 仓库：参考 `docs/design/responsive-v1/README.md` 的单 HAP / 共享工作区状态，以及 EntryAbility 的窗口观察与生命周期释放。未发现其已有安全区/键盘实现，不把它当作验证依据，不修改该仓库。

木笺保持现有包身份、数据目录和页面路由。将编辑状态放入可观察模型，页面只转发生命周期和渲染；按功能组合控制器，复用既有领域 Service/Repository，不引入多 HAP。首页按相同方式分离控制器与视图。安全区放入窗口适配器、共享边距组件/属性；键盘使用 UIContext 的 RESIZE，由系统提供有效高度，不叠加键盘避让 padding。所有平台接口核对当前 SDK 与官方文档。

## 任务与验收

TASK-MOBILE-001：新增窗口适配、状态/控制器与视图模块，修改页面入口和验证脚本。ArkTS 用于 ArkUI 响应式状态、UIAbility 和 Webview 接口。无文档格式/存储结构迁移；可按本提交回退。

验证入口：主机行为回归、布局与安全区策略测试、500 行检查、UTF-8/文档检查、ArkTS UT 与 Release 构建；可用 2in1 的宽/窄/中窗真实运行、输入/保存/切换与菜单验收。手机/平板及旧系统只有实际连接后才标为通过。

## 验证记录

环境：Windows PowerShell、DevEco JBR、当前 API 26 SDK；工程最低 API 22 未提升。开始时工作区干净。生产包身份仍为 `com.markdownworkbench.app`；实机安装使用独立的 `com.markdownworkbench.validation`，升级验证包，不卸载、不清理已有文档。

| 命令 | 结果 |
|---|---|
| `node scripts/test-host.cjs` | 233/233 通过；原有保存/恢复/短读写/交付与拖入回归 |
| `node scripts/test-editor-actions.cjs` | 13 组通过；直接加载真实状态和控制器；大纲/分屏、桥队列隔离、外部打开转发、面板关闭后动作、销毁后的迟到回调隔离 |
| `node scripts/test-window-viewport.cjs` | 8 组通过；原生边界 mock，覆盖重叠取最大值、单位、旋转侧边、空区、键盘不叠加、动态失败、系统安全布局回退、监听释放 |
| `node scripts/check-source-size.mjs` | 118 个手写应用/测试/脚本文件全部 ≤500 行；应用 ArkTS 最大为 HomeController 352 行；仅排除生成的 Web bundle |
| `node scripts/check-source-encoding.mjs` | 183 个文本文件严格 UTF-8 检查通过 |
| `node scripts/check-docs.mjs` | 36 个入口/规格 Markdown 文件通过 |
| `hvigorw.bat test --mode module -p product=default` | BUILD SUCCESSFUL；`build-logs/mobile-test.log` |
| `hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release` | BUILD SUCCESSFUL；`build-logs/mobile-release.log` |
| `node web-tools/build-web.js` | 编辑器资源重新生成；预览 bundle 未变；CI 继续验证 bundle 与源码一致 |
| `git diff --check` | 通过 |

测试明确 stub 了平台、装饰器与 IO，不能替代 ArkUI 原生响应式更新/系统权限。正式签名材料仍未配置，Release 输出 unsigned HAP；保留原有 ArkTS ESObject 等警告，不宣称无警告发行包。

## 实机验收及修正

设备：HUAWEI HAD-W32 / MateBook Pro，OpenHarmony 7.0.0.106 / API 26，3120×2080，1.9px/vp；仅这一台设备在线。窗口由 2091×1394px 依次缩到 1334×1288px（约702vp宽）、689×1024px（约363vp宽）、689×769px（约405vp高），之后重启验证包并重验最终首页与设置。

- 输入 `# MuMark mobile acceptance` 与第二行正文，共 69 字符；真实界面显示未保存及恢复草稿已保留。Ctrl+S 后生成 `MuMark mobile acceptance.md`，状态已保存。
- 依次切换桌面、tablet、phone、低高度布局，正文及 69 字符计数保持；重装同签名验证包后，从最近记录重新打开仍是相同正文。没有通过卸载掩盖升级问题。
- 验证宽/中窗口文档菜单与窄窗口底部操作面板；菜单关闭后可返回首页。新控制器与按断点重排视图不会因此新建文档会话。
- 首轮实机发现 Web 本体已全高而 CodeMirror 只有内容高度：原运行时定义了 `myTheme` 却未加入 `createEditorState` 扩展列表。补回后正文区撑满窗口，重新安装并实际输入、保存通过；同时显式约束 Workspace/Row/Web 容器高度。
- tablet 首页只显示导航与最近两栏；实测发现计数靠右与系统三键重叠，再为此行按实际 caption 宽度避让，最终截图确认分离。
- phone 设置页“默认视图”说明被三个按钮挤成窄列；改为说明与按钮分行，最终截图确认布局。设置行改为最小高度，允许内容增长。
- 低高度编辑页隐藏辅助工具与常规状态栏；恢复失败提示仍保留。查找区限高可滚动，正文可见。低高度首页精简品牌/新建/恢复区，保留打开、资料库、搜索、列表和底部导航；资料库展开后独立滚动，不继续挤占最近列表。
- Native 日志 11:33:54.061 / PID 63514：`safe insets active; keyboard mode RESIZE`。这台自由窗口的四边系统避让量均为 0，仅验证了原生配置执行与桌面 caption；不用于证明非零刘海/导航区域通过。

截图及裁剪坐标见[证据目录](../ux/mobile/README.md)。图片只从 native screenshot 裁取应用窗口，未重新绘制或修饰。

## 安全区域、键盘与生命周期实现

`SafeAreaPolicy` 将窗口相对 px 矩形转成 vp，系统栏、刘海与导航区域按每边最大值合并，避免重复叠加。WindowViewportAdapter 在窗口尺寸与避让区变化时重算；失效时记录日志，回退系统非沉浸安全布局；销毁时释放自己的全部监听。Caption 原生数据已是 vp，不再次换算，并扣除已避让的安全边距。

四个路由页面使用 SafePage。键盘由 UIContext.RESIZE 管理页面高度，安全区不包含 TYPE_KEYBOARD；键盘显示时不重复保留底部导航 padding。BindSheet 使用系统自身布局，不声称 RESIZE 能控制弹层。CodeMirror 的全高主题保留在所有新文档会话扩展中，滚动仍由编辑器管理。

可观察 State 不持有 Web/Repository 等平台对象；Environment 管理每次挂载的依赖和可释放句柄。桥队列由全局改为每个挂载实例拥有。销毁后的控制器即使遇到新挂载重新启用共享状态，也不会接收迟到的大纲/打开回调；实际测试覆盖此情况。文件职责清单见 `entry/src/main/ets/features/README.md`。

## 验收结论与未验证项

| 需求 | 结论与边界 |
|---|---|
| FR-MOBILE-001 | 四页面安全区代码、几何回归、编译与 2in1 配置执行通过；真实手机/平板的非零系统区、刘海和旋转未测 |
| FR-MOBILE-002 | RESIZE 真机配置成功，低高度编辑/查找/首页/资料库及窄设置目测通过；本机只有实体键盘/输入法工具条，未取得手机完整软键盘弹出与收起证据 |
| FR-MOBILE-003 | 69 字符真实输入、保存、宽窄切换、重启后最近打开通过；既有 IO/保存/交付回归通过；本轮未重跑 FileOpen 真授权及拖入完整链路 |
| FR-MOBILE-004 | 应用源码最大 352 行，500 行门禁和行为回归进入 CI；没有靠继承链或 include 片段拼接拆分 |
| FR-MOBILE-005 | 可用 2in1 已验收；无手机/平板/API22–25 实机，不标作全端真机验收完成；提交与推送以 Git 记录为准 |

后续设备验收必须覆盖：手机/平板 API22–25 与当前 API 各自冷启动；横竖屏刘海/导航手势；中文 IME 组合输入及软键盘反复开关；查找、资料库重命名在键盘上方可达；屏幕字体放大；真实 FileOpen/拖入授权与保存。未连接对应设备前，不将这些条目标为通过。

## 官方与 SDK 依据

- [避让区域与窗口沉浸布局](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-1089)：系统栏、刘海、导航与 caption 的归属和动态监听。
- 当前 SDK `api/@ohos.arkui.UIContext.d.ts` 的 setKeyboardAvoidMode 注释：RESIZE 作用于页面，百分比尺寸随页面缩放，不控制 Dialog/BindSheet 等弹层。
- 当前 SDK `api/@ohos.window.d.ts`：AvoidArea 为 px；TitleButtonRect 为 vp；监听必须配对释放。
- 当前 SDK `component/web.d.ts`：UIContext 为 RESIZE 时，Web 的单独 keyboardAvoidMode 不生效，因此不叠加另一套避让。
