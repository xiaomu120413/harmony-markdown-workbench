# 木笺 MuMark：内容安全与文件交付

日期：2026-10-19。状态：实现完成，验证结果及未完成的系统授权验收见 [验证记录](productization-verification.md)。
本文是 SDD 1.0.0 的本轮增量规格，覆盖 FR-SAVE-001～004、FR-FILE-002、FR-SHARE。
用户授权先补内容安全、文件交付，并确认名称为“木笺 MuMark”，与木枢、MuTransfer 同系列。

## 产品范围与验收

| 需求 | 用户结果 | 验收 |
|---|---|---|
| FR-SAFE-001 | 关闭自动保存仍保留恢复草稿 | 编辑通知批处理后立即请求检查点，不等待 1.5 秒保存防抖；连续输入合并快照；后台尝试刷新；失败可见 |
| FR-SAFE-002 | 保存失败、并发编辑不损失已落盘草稿 | 草稿临时文件写全、fsync、rename；失败保留旧检查点；保存旧版本不清除新草稿，旧会话回包被拒绝 |
| FR-SAFE-003 | 保存结果和离开决定可信 | 失败/冲突/忙碌阻止保存并离开，系统返回采用同一入口；不声称尚未确认落盘的内容已保护 |
| FR-DELIVER-001 | 另存为后继续保存新文件 | 选择目标成功写入才切换来源、标题、revision；取消/失败保留原目标；导出副本不切换 |
| FR-DELIVER-002 | 图片随文档交付 | ZIP 含 Markdown 和所引用私有附件；HTML 内嵌私有图片；缺失/超限附件阻止貌似完整的交付并说明原因 |
| FR-DELIVER-003 | 从系统文件管理器打开文档 | 声明 viewData 文件类型；冷启动和 onNewWant 经统一待打开入口；已有未保存编辑先保护，不能被外部打开覆盖 |
| FR-BRAND-001 | 同系列正式名称与图标 | 木笺 / MuMark；沿用 MuTransfer 蓝青渐变、白色主体、薄荷强调的矢量语言；包名不变，保留既有应用数据 |

非目标：账号、云同步、AI、PDF、目录工作区、多标签、任意外部目录递归读取、系统分享收件人发送。
本轮通过用户显式选择的保存目录交付文件，不把复制文本称为文件分享。
瞬间断电/强杀仍可能丢失尚未到达原生层或尚未落盘的输入，不承诺逐键零损失。

## 设计决定（ADR-009 增量）

1. 正文继续以 CodeMirror 为真源。500ms 桥消息批次结束后合并一次恢复快照，独立于自动保存开关；后台也请求检查点。不逐键传输全文。
2. SaveCoordinator 串行检查点，记录会话和版本，拒绝旧版本覆盖。保存完成重新核对最新快照；只有确认同版本才清理检查点。
3. 草稿及内部文件采用写全、fsync、rename。外部 URI 无法保证提供方原子替换，写前检查基线并要求草稿成功；短写视为失败。
4. 文件交付编排进入 DocumentDeliveryService，平台 IO 进入文件基础设施。HTML 渲染与读取在一次 JS 调用中返回，不依赖隐藏预览的旧缓存。
5. ZIP 使用当前 SDK 的 zlib.compressFile（目录输入）生成私有临时包，再复制到用户选择的目标。只包含文档引用的私有附件；解析路径禁止穿越。单附件上限 20MiB，总附件上限 100MiB；HTML 总附件上限 20MiB。超限明确失败。
6. 外部目录中的相对资源尚无目录权限，不能假装完整；检测未解析的本地图片引用时提示用户转为应用附件或取得目录权限后再交付。远程图片保留链接，导出提示其不保证离线显示。
   预览复用相同 Markdown 图片解析和附件路径门控，支持引用式及带空格路径；资源映射总量限制为约 28 MiB base64 字符，失败明确记录且不改正文。
7. 系统打开由 Want 的 uri/type/action 进入单一队列，编辑页先检查保存/草稿结果；取消不能丢弃既有正文。保留原包名 `com.markdownworkbench.app`。

官方依据：[URI skills](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/app-uri-config)、[Want](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/want)。
实现签名以本机 DevEco SDK `ets/api/@ohos.file.fs.d.ts`、`@ohos.zlib.d.ts`、`@ohos.app.ability.Want.d.ts` 为准。

## 任务与提交

| 任务 | 依赖 | 主要文件 | 验证 |
|---|---|---|---|
| TASK-SAFE-001 | 现行保存链 | SaveCoordinator、DraftStore、文件适配器、EditorPage、editor.js | 并发/快照失败/检查点失败 UT，Web bundle 重建，HAP 构建；真机自动保存关闭与恢复 |
| TASK-DELIVER-001 | SAFE | DocumentDeliveryService、附件策略、EntryAbility、HomePage、EditorPage、module.json5 | 附件/取消/失败 UT，HAP，真机另存后继续编辑、ZIP/HTML 应用外检查、外部打开 |
| TASK-BRAND-001 | 无，最后集成 | AppScope、入口资源、首页/帮助、矢量及生成脚本、README | 图标尺寸/透明检查，名称扫描，构建与装机截图 |

SAFE 与 DELIVER 共享编辑会话、检查点和文件 IO，是同一条防丢失交付链，合并为一次内聚实现提交；BRAND 独立提交。文档记录与两次提交配套。

回滚：按上述提交 revert；保留既有正文、草稿 JSON 结构、包名和内部目录，不迁移或删除用户数据。
