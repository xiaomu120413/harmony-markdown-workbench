# 木笺：外部文件入口与编辑操作收拢

日期：2026-10-19。任务：TASK-INTAKE-001（文件进入、来源识别与操作入口的同一交付单元）。承接[前轮规格](productization-2026-10.md)。
状态：实现完成；实际验证和设备范围见配套验收记录。

## 需求与验收

| ID | 用户结果与验收 |
|---|---|
| FR-INTAKE-001 | 文件管理器真实“打开方式”授权可冷/热启动木笺，读到正文并保存回原文件；拒绝或取消不能破坏当前正文 |
| FR-INTAKE-002 | 首页及编辑器可拖入一份 Markdown/txt 文档；异步获取系统拖拽数据，超时/不支持格式/多文件有明确反馈；连续拖入仍可用；原正文先保护，拖入不能让 Web 离开编辑运行时 |
| FR-RECENT-002 | 同一外部 URI 的编码及查询别名合并，保留最新可访问 URI、时间和固定状态；不同目录的同名文件不合并，最近列表显示来源/位置 |
| FR-UX-001 | 编辑工具收为标题、格式、段落、插入、撤销/重做；文件菜单分文档、导出、复制与位置；保留所有原有命令并提供编辑页内打开/新建入口 |

非目标：Office/PDF/ZIP 解析、批量多标签、目录导入、跨设备大文件拖入和扩大系统文件权限。

## 设计决定

- 使用当前 SDK 的 `DragEvent.startDataLoading` 异步取 UDMF 数据；不在主线程同步 `getData()` 等待外部数据。原生入口处理文件拖放，Web 禁止默认文件导航，DOM 兜底防止文件直接被当成正文粘入。
  `onDrop` 设置 `disableDataPrefetch: true`；编辑区拖入时显示原生接收层，避免 ArkWeb 内建逻辑抢先消费数据。15 秒超时后调用 DragController 取消任务并忽略迟到结果。
- 打开方式和选择器继续编辑原文件；拖入由系统复制至独立缓存暂存目录，再原子导入“我的文档”，明确提示“导入副本”，不把缓存 URI 当长期来源。相同导入名称及正文可复用已有内置副本，不覆盖不同正文的同名文件。仅接收单文件 `.md/.markdown/.txt`；不支持类型保留当前正文并说明。超时和完成后清理暂存文件，失效回调不能打开文档。
- 最近记录按来源身份合并，内部资料库与外部文件分开。保留 URI 原值供 IO；仅比较键解码和去除查询/片段，不按 basename 合并。清理本轮先前调试产生的应用缓存 URI 最近记录（不清除正文），避免保留会失效的来源。
- 使用已有 ArkUI Menu/MenuItemGroup 与颜色/尺寸规范收拢操作，避免新增页面或新视觉体系。屏幕较窄仍可横向滚动，但常用操作入口数量减少。
  菜单使用命名 `@Builder` 引用，让当前 ArkTS 编译器生成正确的 builder 包装；自由窗口内显示，显式按钮点击控制展开状态。匿名包装函数在当前构建链中不会生成有效的菜单绑定，已在真机验证后修正。

SDK 依据：`component/common.d.ts`（DragEvent）、`api/@ohos.data.unifiedDataChannel.d.ts`、`@ohos.data.uniformDataStruct.d.ts`、`component/web.d.ts`，均来自本机 DevEco SDK。注册依据：[官方 URI skills](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/app-uri-config)。

## 实施与验证

| 任务 | 文件与依赖 | 验收 |
|---|---|---|
| TASK-INTAKE-001 | 入口策略、拖拽适配、Home/Editor、Web、RecentFileList、DocumentSidebar；依赖原保存链和已有 EntryAbility 系统入口 | 策略/身份/固定状态 UT、超时/数据失败、HAP；真机冷/热打开及保存、重复拖放/不支持格式/取消；菜单与最近来源截图及命令验收 |

边界与回滚：不改变包名、正文格式和存储目录；提交可独立回退。真实结果与未验证项记录于[验收记录](file-intake-verification.md)，不能将计划写为已通过。
