# 页面职责与状态边界

页面入口只连接路由、AppStorage 事件和生命周期。功能区使用同一可观察状态，不按断点新建文档会话。所有手写源码最多 500 行，CI 执行 `scripts/check-source-size.mjs`。

| 文件/目录 | 职责 |
|---|---|
| `editor/EditorState` | 可观察编辑状态、选区、视图、查找和文档身份，不持有平台对象 |
| `editor/EditorEnvironment` | 单次挂载的 Web 控制器、Repository、保存协调器与可释放句柄 |
| `editor/EditorController` | 页面命令入口、Web 调用和面板调度；直接组合功能实现，无纯运行时转发层 |
| `editor/EditorLifecycle` | 设置同步、监听和定时任务的注册/释放 |
| `editor/EditorDocuments` | 外部打开、拖入、文档切换与加载 |
| `editor/EditorPersistence` | 快照、草稿、持久化、冲突和离开保护 |
| `editor/EditorPreview` | 预览同步、大纲与窗口空间决策 |
| `editor/EditorFind` | 查找替换及编辑状态分发，规则仍来自 domain |
| `editor/EditorDelivery` | 另存为、导出、复制及图片插入 |
| `editor/*Screen/Header/Workspace/FindPanel/CommandBar/FileActions` | ArkUI 视图与事件转发，无持久化实现 |
| `home/HomeState`、`home/HomeEnvironment` | 首页可观察数据与平台依赖分开 |
| `home/HomeController` | 资料库、最近记录、搜索、重命名/回收及路由编排 |
| `home/*Screen/Compact/Navigation/RecentList/Welcome/LibraryPanel` | 首页分区展示；共享 HomeState |
| `settings/SettingsState`、`settings/SettingsViewModel` | 设置展示状态与加载、校验、串行保存编排；页面无 Preferences/DraftStore 操作 |
| `recovery/RecoveryState`、`recovery/RecoveryViewModel` | 恢复展示状态与磁盘校验、恢复/副本/清理编排；domain 决定恢复规则 |
| `preview/HtmlPreviewState`、`preview/HtmlPreviewViewModel` | HTML 只读状态与读取、独立 Web 装载；不接入 Markdown 保存或 JSBridge |

安全区域由 `infrastructure/window/WindowViewportAdapter` 发布，四个路由页面统一使用 `components/SafePage`。RESIZE 负责键盘缩放；组件不再次叠加键盘高度。设备窗口变小只改变布局状态，不重新创建控制器、Web 文档或 SaveCoordinator。

桥消息队列直接由每次挂载的 EditorEnvironment 持有，退出时清空并断开回调。SaveCoordinator 的回调由 Controller 直接组装，加载与另存仍各自创建新协调器并设置真实 session/version。侧栏偏好由现有 MetadataStore 使用原键读写，不单独创建同库 Store。

这里的 EditorController / HomeController 是 ViewModel 命令入口，命名不代表 MVC 的页面控制器；State 是绑定到 ArkUI 的可观察展示数据。平台对象、Promise、定时器和订阅放在非观察 Environment；纯业务规则放 domain；文件与元数据读写放 infrastructure。设置/恢复使用显式 ViewModel 命名，职责遵循相同边界。

不增加观察计数器或强制重绘。查找和预览使用真实 sessionId/version 快照并核对当前查询条件；文档加载以实际读 Promise 区分先后操作。`Date.now()` 用于保存调度、历史时间或唯一文档会话，不充当 UI 刷新键。

编辑器 State 只保留 35 个存储字段；命中数量从匹配列表派生，保存文案和冲突可见性从 SaveState 派生。会话、待加载正文、文件版本、缓存和 AppStorage 适配放在现有 Environment，不观察、不强制刷新。帮助直接并入设置分组。
