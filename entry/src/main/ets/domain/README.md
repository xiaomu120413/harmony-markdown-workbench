# domain/ 层

与 UI 和平台无关的领域模型与规则（SDD 7.3：文件访问、编辑器桥接、渲染、元数据、恢复解耦）。

- `document/`：DocumentSource、FileRevision、DocumentRecord、DocumentFileAdapter 接口等（M1-01）
- `recovery/`：草稿恢复决策逻辑（M4-04 / FR-SAVE-004）
- `settings/`：设置模型与默认值（M5-03）

规则：

- 本层不 import ArkUI 与文件系统 API，纯 ArkTS/TS 逻辑，便于单元测试（SDD 11.1）。
- 领域类型定义放这里，实现放 `services/` 与 `infrastructure/`。