# services/ 层

应用服务与编排层（SDD 8.1），当前实际文件：

- `SaveCoordinator.ets`：保存状态机、版本门控自动保存、串行化与检查点（M4-01 / A1）。
- `EditorBridge.ets`：与 ArkWeb 编辑运行时的 JSBridge 协议解析与消息分发（M2-02）。
- `DocumentImportService.ets`：系统选择器/拖入 URI 的导入与副本落盘。
- `DroppedDocumentReader.ets`：拖拽数据读取（异步 getData，避免同步阻塞）。
- `DocumentDeliveryService.ets`：另存 Markdown、导出图文 ZIP、导出独立 HTML 与附件资源内嵌。

规则：

- 服务不直接操作 Page 组件；通过 ViewModel 或回调与 UI 交互。
- 文件读写细节下沉 `infrastructure/`，服务层只编排。（SDD 6.5）
- 交付/保存失败必须返回明确结果，不得把失败写成成功；正文写回由编辑器层用 `runJsChecked` 收口。
