# services/ 层

应用服务与编排层（SDD 8.1）：

- `DocumentService.ets`：文档会话管理（状态机驱动）
- `SaveCoordinator.ets`：保存状态机、自动保存、串行化（M4-01）
- `ConflictDetector.ets`：外部变更检测（FR-FILE-004）
- `ShareService.ets`：系统分享（M5-02）
- `EditorBridge.ets`：与 ArkWeb 编辑运行时的 JSBridge（M2-02）

规则：

- 服务不直接操作 Page 组件；通过 ViewModel 或回调与 UI 交互。
- 文件读写细节下沉 `infrastructure/`，服务层只编排。（SDD 6.5）