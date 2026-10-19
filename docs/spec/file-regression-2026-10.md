# 文件链路拆分后回归（TASK-FILES-001）

## 范围与验收

基线 `128433d`，在现有单 HAP 内回归打开、真实打开方式授权、拖入、保存、另存为、Markdown / ZIP / HTML 导出。保留正式安装与用户文档，使用独立 validation 包和自建样本。

- 系统选择器打开与取消，热 / 冷启动打开方式；原位保存内容和编码正确。
- 首页及编辑器连续拖入，拒绝不支持格式后仍可继续导入，未保存切换可取消。
- 另存为取消不改目标，成功后继续保存只改新目标；标题反映实际文件名（含无扩展名）。
- 导出副本不改变当前目标，ZIP / HTML 带齐本地图片；落盘取回核对正文及附件。
- 旧页面的选择器 / 交付回调不能写新页面状态或重新操作 Web 控件。

## 设计与修复

保留已有 Service / Controller 职责：文件名展示修复在 DocumentDeliveryService；异步结果由 EditorPersistence / EditorDocuments / EditorDelivery 检查控制器存活和原文档会话。无新增权限，无路由或分包变更。真实选择器允许任意文件名，扩展名白名单不能用于决定是否展示实际名字。

回滚为撤销本任务提交，不迁移已有文档或元数据。

## 验证记录

环境：2026-10-19，Windows / DevEco 本地 SDK，HUAWEI HAD-W32（MateBook Pro），HarmonyOS 7.0.0.106 / API 26。独立包 `com.markdownworkbench.validation` 覆盖安装，未卸载或清空正式包。修复版签名包 2,433,162 bytes；设备验收在 11:41—11:58 完成，中途避开其他任务的设备操作后重新验收冷启动。

### 实机流程

| 场景 | 证据与结论 |
| --- | --- |
| 打开选择器与取消 | 首页打开后取消，仍在首页；再次选择 `regression-1142-source.md`，中文、emoji 正确显示 |
| 原位保存与格式 | 自建 42-byte BOM / CRLF 样本追加 `SAVE_ORIGINAL_1143` 后 Ctrl+S；取回 62 bytes，BOM 及所有 CRLF 保留 |
| 另存为取消 | 取消系统保存框后追加 `AFTER_CANCEL_1143`，取回原文件 81 bytes，仍写原目标 |
| 热启动打开方式 | 文件管理器长按样本 → 打开方式 → 木笺；追加 `OPEN_WITH_HOT_1150` 并保存，原文件取回确认标记 |
| 冷启动打开方式 | 修复版安装后 force-stop validation，从文件管理器真实菜单打开；追加 `OPEN_WITH_COLD_1153`，取回 122 bytes，BOM / CRLF 与两次打开方式标记均存在；[截图](../ux/file-regression/cold-open-with.jpg) |
| 无扩展名另存为 | 系统选择器使用 `rg53`，标题、最近记录立即显示实际名字；追加 `FINAL_SAVEAS_1154` 后 Ctrl+S，131-byte 新文件有标记，122-byte 原文件不含标记；[截图](../ux/file-regression/save-as-actual-name.jpg) |
| 图文 ZIP | 未保存时追加 `EXPORT_FRESH_1155`，通过系统保存框导出 `rg55.zip`；409 bytes，Python zipfile 校验 CRC 无错误，只含 `document.md` 和 `attachments/test.png`，正文含最新标记，图片与原 77-byte PNG 逐字节一致 |
| 网页 HTML | 同一会话导出 `rg55.html`，1763 bytes；含最新标记，提取 data URI 后 base64 解码与 PNG 一致 |
| Markdown 副本 | 明确确认“不包含图片附件”后导出 `rg55.md`；93 bytes，与 ZIP 正文逐字节一致。导出后原会话仍未保存，点击保存写回内部 `library/delivery.md`（99 bytes，保留原 CRLF），未切换为副本目标 |
| 不支持格式后继续拖入 | 从文件管理器拖 `rg55.html` 到编辑区，明确拒绝且保留正文；紧接着拖 Markdown 成功，正文 107 字符，无重启；[拒绝截图](../ux/file-regression/unsupported-drop.jpg) |
| 未保存拖入与取消 | 追加 `DIRTY_DROP_CANCEL_1157` 后拖另一个 MD，出现保护提示；取消后仍是原正文，且 drafts JSON 包含该标记；[提示](../ux/file-regression/dirty-drop-prompt.jpg)、[取消后](../ux/file-regression/dirty-drop-cancelled.jpg) |
| 首页拖入 | 保存上述自建样本后返回首页，拖入 `rg55.md`，进入编辑器显示 79 字符和“编辑的是副本”；[截图](../ux/file-regression/home-drop.jpg) |

数据准备和核对通过 `hdc file send/recv` 完成，授权行为全部通过真实系统选择器 / 文件管理器 / 鼠标拖动完成；手工启动 Want 不作为授权证据。首次自动输入长文件名发生工具丢字，实际另存成 `regression-143-`；它暴露了旧标题回退问题，修复后用短文件名 `rg53` 在保存前截图确认输入并重测。该工具问题不计为应用输入框缺陷。

截图只裁切木笺 validation 窗口并缩小，不修饰内容；原截图时间与裁切参数见 [captures.json](../ux/file-regression/captures.json)。自建样本、原始日志、签名材料和取回产物留在被忽略目录，不提交用户文档。

### 自动化与构建

- `node scripts/test-host.cjs`：234/234 通过，新增无扩展名与自定义扩展名交付文件名用例。
- `node scripts/test-editor-actions.cjs`：13 组通过。
- `node scripts/test-file-transactions.cjs`：14 组通过，运行真实 Controller / SaveCoordinator，mock 系统边界，覆盖另存为取消 / 失败 / 成功后继续保存、三种导出不改目标、打开 / 重选的过期结果、交付及照片选择在页面销毁后的结果。已加入 CI。
- `node scripts/test-window-viewport.cjs`：8 组通过。
- `hvigorw.bat test --mode module -p product=default`：BUILD SUCCESSFUL；日志 `build-logs/files-regression-test.log`。
- `hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release`：BUILD SUCCESSFUL；日志 `build-logs/files-regression-release.log`。保留既有 ESObject / 废弃 API 告警；Release 未签正式证书。
- 独立验证包本地构建、签名、覆盖安装成功；签名过程未改变生产 bundle 配置。
- `node scripts/check-source-size.mjs`、`node scripts/check-source-encoding.mjs`、`node scripts/check-docs.mjs`、`git diff --check`：通过，所有手写代码 / 测试 / 脚本不超过 500 行。

### 核对摘要

| 取回样本 | bytes | SHA-256 |
| --- | ---: | --- |
| 冷启动原文件 | 122 | `2e1ba3de4dc770ff260917b447b264caab9050a0c9819c88201461a823cbb1ea` |
| 无扩展名新目标 rg53 | 131 | `db48e8f19ee38e094c1f0a60a2fe08cd90ada8375821f15d6f2e07d15d20a4e9` |
| Markdown 副本 | 93 | `6f350ebbf3529399f236443085dea7b125140ed526ecbcc1206a07a6839370e5` |
| 图文 ZIP | 409 | `dcdf76788d0fa07510fac361cf196764d020548877efe05d29f4dade7bd2d2fd` |
| HTML | 1763 | `2e726c58db8777bea1ce39e712ac8ec34b536e396ab3a46a3147ab7380744a34` |

未覆盖：无实体手机 / 平板和 API 22—25 设备；未模拟真实磁盘耗尽、掉电、云盘提供者授权撤销及传输中断。相应 IO / 过期回调异常使用主机测试覆盖，不能替代这些平台实测。正式包升级因原签名不可用而未验收；本轮未改权限、SDK 下限、路由或 HAP 划分。
