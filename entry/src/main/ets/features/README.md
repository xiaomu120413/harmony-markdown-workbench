# 页面职责与状态边界

页面入口只连接路由、AppStorage 事件和生命周期。功能区使用同一可观察状态，不按断点新建文档会话。所有手写源码最多 500 行，CI 执行 `scripts/check-source-size.mjs`。

| 文件/目录 | 职责 |
|---|---|
| `editor/EditorState` | 可观察编辑状态、选区、视图、查找和文档身份，不持有平台对象 |
| `editor/EditorEnvironment` | 单次挂载的 Web 控制器、Repository、保存协调器与可释放句柄 |
| `editor/EditorController` | 供页面使用的命令入口；组合功能控制器，无继承链 |
| `editor/EditorLifecycle` | 设置同步、监听和定时任务的注册/释放 |
| `editor/EditorDocuments` | 外部打开、拖入、文档切换与加载 |
| `editor/EditorPersistence` | 快照、草稿、持久化、冲突和离开保护 |
| `editor/EditorPreview` | 预览同步、大纲与窗口空间决策 |
| `editor/EditorFind` | 查找替换及编辑状态分发，规则仍来自 domain |
| `editor/EditorRuntime` | Web 调用、命令分发、文件面板调度与帮助 |
| `editor/EditorDelivery` | 另存为、导出、复制及图片插入 |
| `editor/EditorBridgeChannel` | 每个挂载会话独立的非观察消息队列，桥回调只入队 |
| `editor/*Screen/Header/Workspace/FindPanel/CommandBar/FileActions` | ArkUI 视图与事件转发，无持久化实现 |
| `home/HomeState`、`home/HomeEnvironment` | 首页可观察数据与平台依赖分开 |
| `home/HomeController` | 资料库、最近记录、搜索、重命名/回收及路由编排 |
| `home/*Screen/Compact/Navigation/RecentList/Welcome/LibraryPanel` | 首页分区展示；共享 HomeState |

安全区域由 `infrastructure/window/WindowViewportAdapter` 发布，四个路由页面统一使用 `components/SafePage`。RESIZE 负责键盘缩放；组件不再次叠加键盘高度。设备窗口变小只改变布局状态，不重新创建控制器、Web 文档或 SaveCoordinator。
