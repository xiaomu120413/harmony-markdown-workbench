# components/ 层

ArkUI 可复用组件目录。职责（对应 SDD 8.1）：

- `SaveStatus.ets`：保存状态指示（M5-01 / FR-SAVE-001）
- `RecentFiles.ets`：最近/固定文件列表（M5-01）
- `MarkdownToolbar.ets`：移动端 Markdown 快捷栏（M2-04）
- `OutlinePanel.ets`：大纲侧栏（M3-03）
- `ConflictDialog.ets`：外部冲突对话框（M4-03）

规则：

- 组件不直接调用文件系统 API（SDD 7.3：视图不得直接调用全部文件 API）。
- 组件只消费 `@Prop`/`@Link`/回调，业务状态由上层页面或 ViewModel 提供。