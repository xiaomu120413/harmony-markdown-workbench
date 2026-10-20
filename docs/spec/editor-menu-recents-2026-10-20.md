# 编辑菜单与最近文档整理

## 范围与验收

- 标题、格式、段落、插入菜单各自绑定固定内容；关闭时不清空共享菜单状态，消除内容切换闪烁。
- 移除可见重做按钮，保留撤销和原有重做快捷键。
- 最近列表仍在左侧，减少边框与时间信息；“固定”统一改称“置顶”，提供可见置顶、删除入口。
- 删除应用内文档须确认，成功后移入现有回收站、移除最近记录，可从我的文档恢复。
- 外部文件不冒充应用内文档删除，提示在文件管理器处理；当前打开的文档须先切换再删除。
- 不新增权限、状态层或通用抽象；手写文件不超过 500 行。
- 自动改名或删除后的失效应用内记录不再显示，外部记录仍保留授权恢复入口。

## 实现与边界

菜单使用 SDK 原生 bindMenu(isShow, CustomBuilder, MenuOptions)，Builder 参数固定为按钮种类。
模拟器上无 isShow 参数的绑定未响应点击，因此保留一个组件内部显隐字段；移除 EditorState 的 activeToolMenu，关闭时不再改变菜单内容。
点击菜单项时先关闭显隐字段，再执行命令，避免正文刷新将正在关闭的菜单重新呈现。
页面只分发操作，首页与编辑器各自控制器调用已有 InternalFileSource.trashLibrary、RecentFileList 和元数据存储。
回滚时恢复此次提交即可，不改变文件或元数据格式。

## 验证

2026-10-20，Windows / DevEco Studio 当前 SDK，兼容与目标版本仍为 API 22。

| 验证 | 结果 |
|---|---|
| `node scripts/test/test-editor-actions.cjs` | 39 场景通过；涵盖取消/确认删除、失败保留记录、正在打开的文档保护、确认后切换目标再检查、置顶、元数据失败提示、失效内部记录过滤、文件名越界拒绝 |
| `node scripts/test/test-host.cjs` | 255/255 通过（平台 IO mock） |
| `node scripts/test/test-file-transactions.cjs` | 24 场景通过（平台选择器 mock） |
| `hvigorw.bat test --mode module -p product=default` | BUILD SUCCESSFUL |
| `hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release` | BUILD SUCCESSFUL；正式包名仍为 com.mumark.app，正式签名配置为空，构建产物未签名 |
| `node scripts/check/check-source-size.mjs` | 128 个手写源码/测试/脚本均不超过 500 行 |
| UTF-8、文档链接检查及 `git diff --check` | 通过 |

手机：Pura 90 模拟器 API 24，1320×2856，独立验证包 com.mumark.menutest，与既有验证包及正式包并存，不卸载用户应用。

- 标题 H3、格式斜体、段落任务列表、插入分隔线：内容写入成功，随后 UI 树中菜单项消失；关闭过程不再把菜单内容切换到插入项。
- 撤销按钮可还原斜体操作，Ctrl+Y 可恢复同一操作；重做可见按钮已移除。
- 最近列表图钉可点击，preferences 中 pinned=true 已持久化。自动改名遗留记录由 2 条收敛为实际存在的 1 条。
- 垃圾桶取消：源文件仍在；确认：源文件进入私有 library/.trash；“我的文档 → 回收站 → 恢复”成功。
- 回收站与恢复后的 SHA-256 均为 `33f941dec038797052d6d98100889299e987982f29e3b25179f8184296b168cb`。
- hdc 文件检查仅针对本次独立验证包的自建测试文档。

未验证：本次未占用正在运行其他任务的 2in1，平板不在线，左侧侧栏的本轮物理设备交互仍待复核；外部原文件删除没有接入，按钮明确提示去文件管理器处理，不将“移除最近记录”冒充删除文件。没有新增敏感权限。
