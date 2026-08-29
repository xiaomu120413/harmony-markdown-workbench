# infrastructure/ 层

平台与数据访问实现（SDD 8.1）：

- `file/InternalFileSource.ets`：内部资料库文件适配器（M1-01 / FR-FILE-001）
- `file/ExternalUriFileSource.ets`：外部 URI 文件适配器（M1-01 / FR-FILE-002）
- `metadata/MetadataStore.ets`：元数据存储（索引，不存正文，M1-02）
- `recovery/DraftStore.ets`：草稿日志存储（M4-04）

规则：

- 本层实现 `domain/document` 定义的 `DocumentFileAdapter` 契约，通过同一套契约测试（SDD 15.2）。
- 不把正文唯一副本写入元数据存储（FR-FILE-001）。