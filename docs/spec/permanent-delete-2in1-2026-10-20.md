# 直接删除与 2in1 回归 ST-FILE-DELETE-001

## 需求与范围

用户在 2026-10-20 明确调整：删除即删除，不再提供回收站恢复。
本记录覆盖前一轮“移入应用回收站”的新删除行为，历史验收记录保留其当时结论。

- REQ-FILE-DELETE-001：最近列表、编辑器左侧列表和资料库菜单统一显示“删除”，确认弹窗说明不可恢复；取消不修改文件。
- REQ-FILE-DELETE-002：确认后删除应用内源文件及其对应恢复草稿，成功才移除最近记录；失败不得提示成功。
- REQ-FILE-DELETE-003：删除当前打开文档仍要求先切换，防止自动保存写回；外部文件仍提示使用文件管理器，不假装删除原文件。
- REQ-2IN1-001：MateBook Pro 实测四组菜单关闭、左侧最近列表、置顶、确认/取消删除和重启后状态。

## 设计与 Story

ST-FILE-DELETE-001：将 InternalFileSource 的回收操作替换为校验文件名后的 unlinkSync；首页和编辑器保持既有操作分发。
移除回收站 UI、两个回收站状态字段和只服务于恢复的控制器/文件适配器代码；不增加新的状态层或抽象。
回归发现保存新文件后侧栏不立即刷新：将侧栏刷新统一接到既有 trackRecent 保存成功路径，去掉打开路径的重复刷新；搜索无结果补充提示。
使用已有 DraftStore.remove 清理对应 internal:library/... 草稿；不清理其他文档草稿、共享附件或既有旧回收站内容。
旧回收站不再显示，存量文件不在升级时自动抹除或恢复。新删除没有回收副本。

涉及文件：InternalFileSource、HomeController/State/LibraryPanel、EditorDocuments，及相关测试、使用说明和本记录。
文件系统能力使用当前 SDK 的 fileIo.unlinkSync（API 9 起支持的沙箱路径操作），无新增权限，兼容下限仍为 API 22。
回滚代码不会恢复已经确认删除的文件；测试仅删除本轮创建的验收文档。

## 验证记录

2026-10-20，Windows / DevEco Studio 当前 SDK，正式包名 com.mumark.app，最低/目标 API 22，未新增权限。

| 命令 | 结果 |
|---|---|
| `node scripts/test/test-host.cjs` | 258/258 通过；新增真实临时文件删除、不建立回收副本、路径越界拒绝、目录拒绝、保留其他文件及旧回收文件测试 |
| `node scripts/test/test-editor-actions.cjs` | 40 场景通过；删除确认/取消、失败、当前文档保护、对应草稿清理、元数据失败提示、新文件保存后刷新侧栏 |
| `node scripts/test/test-file-transactions.cjs` | 24 场景通过 |
| `hvigorw.bat test --mode module -p product=default` | 205/205 通过，Failure: 0、Error: 0；BUILD SUCCESSFUL |
| `hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release` | BUILD SUCCESSFUL；正式 Release 仍未配置签名 |
| `node scripts/check/check-source-size.mjs` | 128 个手写源码/测试/脚本均不超过 500 行 |
| 源码 UTF-8、文档链接检查及 `git diff --check` | 通过 |

2in1：HUAWEI MateBook Pro（HAD-W32），OpenHarmony 7.0.0.106 / API 26，3120×2080。
使用独立验证包 com.mumark.menutest 覆盖升级，不卸载应用；验收前后原有两份文档 SHA-256 不变。

1. **菜单关闭：通过。** 浮动窗口 2090×1394 下，标题 H2、格式加粗、段落任务列表、插入分隔线均实际写入正文。每组选中前截图、点击后连续 6 次 snapshot_display 采样，未见关闭后重新弹出或切成其他菜单，UI 树无残留 MenuItem。最大化 3120×1955 后标题菜单 Escape 关闭正常。
2. **左侧最近列表：通过并修复。** 新文档保存后即时出现在侧栏；图钉置顶、置顶筛选、搜索、清空搜索均正常；无匹配结果显示提示。当前打开文档的删除被阻止，文件保留。
3. **取消删除：通过。** 自建 MuMark-PC-Delete-1737.md 的删除弹窗明确“直接删除，无法恢复”；取消后源文件 78 字节及自建对应恢复草稿 254 字节均仍存在。
4. **确认删除：通过。** 编辑器侧栏确认后，源文件与 internal:library/... 对应草稿均不存在，最近记录移除；旧 .trash 清单完全不变，没有新增回收副本。
5. **资料库删除：通过。** “我的文档”行菜单只显示“删除”；删除第二份自建验收文档成功。资料库不存在回收站或恢复入口。
6. **重启：通过。** `hdc ... shell aa force-stop com.mumark.menutest` 后重新启动，两份测试文档均未重新出现，原有最近记录和文档仍在；所有自建验收文档已清理。
7. **安装：通过。** 修复后验证包已留在 2in1；手机模拟器 API 24 同步覆盖升级，首页启动冒烟检查通过，未执行本轮完整手机回归。

截图证据：[标题菜单关闭采样](../ux/2in1-menu-close-2026-10-20.jpg)、[直接删除确认](../ux/2in1-direct-delete-2026-10-20.png)。完整采样和命令日志在忽略目录 build-logs/pc-menu-*-capture.log、permanent-delete-*.log，未提交签名材料或构建产物。

边界：以上是设备截图连续采样和 UI 状态检查，不是高帧率录屏，不能据此量化每帧延迟；外部原文件仍须到文件管理器删除；API 22 真机和平板本轮未回归。旧回收文件只保留在磁盘上，不自动恢复或抹除。现存崩溃草稿恢复功能继续服务其他未主动删除的文档。
