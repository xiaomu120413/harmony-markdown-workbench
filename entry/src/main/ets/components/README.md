# components/ 层

ArkUI 可复用组件目录（对应 SDD 8.1），当前实际文件：

- `SafePage.ets`：四个路由页共用的安全区域容器（顶部/底部避让，键盘不重复叠加）。
- `DocumentSidebar.ets`：编辑页文档侧栏（最近/固定/资料库三段筛选 + 搜索）。

其余编辑页分区（顶栏、工具栏、查找面板、状态栏等）位于 `features/editor/`，首页分区位于 `features/home/`；它们共享可观察 State，不另建跨页组件。

规则：

- 组件不直接调用文件系统 API（SDD 7.3：视图不得直接调用全部文件 API）。
- 组件只消费 `@Prop`/`@Link`/回调，业务状态由上层页面或 ViewModel 提供。
