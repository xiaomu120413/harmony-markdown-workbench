# API 22 平板与手机回归 ST-DEVICES-002

2026-10-20，基线 56a3661，初始工作区干净。REQ-DEVICES-002：覆盖最低 API 22 的真实平板及现有手机模拟器，检查冷启动、系统文件选择授权、UTF-8 中文/emoji、保存与重开、HTML 资源补齐和导出、横竖布局、安全区及软键盘。取消和失败不得覆盖当前正文或伪装保存成功。

沿用单 HAP、现有控制器与平台适配；仅对本轮复现的问题做最小修复，不新增封装或观察状态，手写文件不超过 500 行。ST-DEVICES-002 使用自建样本和 com.markdownworkbench.validation，保留正式安装和用户数据；不得以注入 URI 替代系统文件授权。

验证计划：MatePad Pro PCE-W30 / HarmonyOS 6.0.2.130 / API 22 真机，Pura 90 / HarmonyOS 6.1.1.125 / API 24 手机模拟器，安装同一验证包。实际 UI 选择/保存，取回产物核对字节；截图和日志记录证据与未覆盖项。若出现缺陷，先在此补设计与回滚边界，再实现和回归。未实际执行的设备场景不标通过。

## 复现与最小修复

API 24 手机模拟器声明 FolderSelection 系统能力，但 FOLDER 模式仍打开普通文件选择器，不能选择当前目录；API 22 MatePad 实际目录选择成功。故 EditorDelivery 仅在系统能力存在且设备类别为 tablet / 2in1 时提供目录入口，手机与其他类别直接选资源文件。依据实际平台行为区分设备类别，不按型号或尺寸推断，不增封装或可观察状态。控制器回归覆盖手机能力误报、平板、2in1、无能力和未知类别。回滚只恢复入口判断，不涉及正文/附件格式和授权数据迁移。

API 22 真机查找输入时，首个字符产生匹配后，setSelectionRange 内部 view.focus() 抢走原生查找框焦点，后续字符进入正文。修复在既有 Web API 增加默认保持原行为的 focus 参数，查找定位显式传 false；大纲等现有导航继续使用默认值。不新增状态或抽象，控制器测试及真实连续输入验证焦点与正文保护。

## 验证记录

期间已有预览 iframe 复用提交 c6e9fb8 进入同一工作区；保留其已提交实现，最终重新生成 Web 产物、构建并在两端安装同一验证 HAP，重新打开已保存文档和取消 HTML 插入。本轮只提交此处两项修复及对应测试、构建产物和证据。

| 场景 | API 22 平板真机 | API 24 手机模拟器 |
|---|---|---|
| 系统选择器打开 Markdown | 已通过真实授权打开 75 字节 UTF-8/CRLF 样本 | 同左 |
| 编辑、保存与重开 | 原位保存 94 字节，中文、🙂/🌲 和 CRLF 保留；进程重启可重开 | 原位保存 93 字节，原始字节与 CRLF 保留；模拟器重启后可重开 |
| HTML 插入与资源 | 系统目录选择器授权，CSS/PNG 随附件，保留原文；插入后 Markdown 156 字节 | 修复后直接进入资源文件选择器，分次选择 CSS/PNG，最终 156 字节；引用在当前光标处插入 |
| 预览隔离 | 紫色文字、黄色背景和绿色图片正常；NO_SCRIPT_1020 保留，脚本未执行 | 同左 |
| 查找焦点 | 修复后连续输入 API22，查找框完整接收且保持焦点，1/2 命中，正文不变 | API24 连续输入及 1/2 命中通过，UI 树确认原生输入框 focused=true、Web 正文 focused=false |
| 布局与软键盘 | 实体横屏 2880×1920、竖屏 1920×2880，系统栏/导航区域可见；正文和查找随键盘缩小，保存可达 | 1320×2856 竖屏，键盘显示时隐藏非必要工具，查找面板可滚动，保存可达 |
| 另存为后继续保存 | 新目标 tablet-api22-saveas-1020.md 得到 165 字节，原 156 字节文档不变 | 新目标 phone-api24-final-1020.md 得到 165 字节，原文档不变 |
| 中文 IME 组合提交 | 点击软键盘 n/i，实际候选“你”提交并保存，新目标 169 字节；有组合中与提交后截图 | 本轮未测完整拼音候选链路 |
| 图文 ZIP | 实际系统保存 925 字节，CRC、正文、附件及 PNG 字节核对通过 | 923 字节，同样核对通过 |
| HTML 导出 | 系统保存 3269 字节，sandbox 内容与 ZIP 附件一致 | 3268 字节，同样核对通过 |
| 最终包取消插入 | 最终包重新打开 HTML 选择器后关闭，169 字节正文不变 | 取消后 165 字节正文不变 |

另存与导出按现有产品行为规范化为 LF，原位保存继续保留 CRLF；验证分别核对，不把两种交付混为逐字节同格式。中文/emoji 的编码验证来自原样本及保存字节；工具粘贴补充平面 emoji 时曾在系统剪贴板变成问号，测试标记中的问号已通过真实撤销/删除清理，不以该工具限制判断应用编码损坏。查找修复前的误输入已通过编辑器撤销恢复，并核对与 156 字节已保存正文一致。

[证据清单](../ux/api22-mobile-2026-10-20/evidence.json)记录同一最终验证 HAP 哈希、31/31 产物字节/结构检查、7 张原生截图的来源尺寸与等比缩放信息。包括[横屏查找与键盘](../ux/api22-mobile-2026-10-20/tablet-find-fixed.jpg)、[竖屏查找与键盘](../ux/api22-mobile-2026-10-20/tablet-portrait-keyboard.jpg)、[手机查找焦点](../ux/api22-mobile-2026-10-20/phone-find-fixed.jpg)、[拼音组合中](../ux/api22-mobile-2026-10-20/tablet-ime-composing.jpg)、[候选提交](../ux/api22-mobile-2026-10-20/tablet-ime-committed.jpg)、[平板最终包预览](../ux/api22-mobile-2026-10-20/tablet-final-preview.jpg)、[手机最终包预览](../ux/api22-mobile-2026-10-20/phone-final-preview.jpg)。截图仅缩放，没有重绘。

命令、环境与结果：

- Windows / 当前 DevEco SDK / 内置 JBR，`node scripts/test-host.cjs`：254/254；editor-actions 24 场景、file-transactions 24 场景、page-viewmodels 7、external-access 9、window-viewport 8、html-preview 8、html-resources 10、html-embed 11 组通过。真实模块执行，平台 IO/装饰器为显式 stub，不替代上述设备验证。
- `node web-tools/build-web.js` 重新生成本地 Web 资源。`hvigorw.bat test --mode module -p product=default`、`hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release` 均 BUILD SUCCESSFUL，日志为忽略目录 build-logs/api22-test.log、api22-release.log。验证包构建后恢复正式 bundleName 再构建 Release；保留既有弃用/ESObject 等警告。
- HDC 仅推送自建样本、安装验证包、取回已由系统选择器授权保存的产物；实际打开/资源选择/导出使用系统 UI。`python build-logs/api22-regression/verify_delivery.py`：31/31 通过。辅助脚本、原产物与完整日志保存在忽略目录。
- `node scripts/check-source-size.mjs`、`node scripts/check-source-encoding.mjs`、`node scripts/check-docs.mjs`、`git diff --check` 提交前检查通过，所有手写文件不超过 500 行。没有新增可观察状态或封装。

未验证：真实手机/API 22 手机、手机横屏、两端真实跨应用拖放、系统字体放大与读屏完整矩阵、云盘提供方、物理设备重启及正式签名覆盖升级。手机横屏尝试中模拟器实例离线，旋转命令未成功；重新启动既有实例后继续回归，不能将其写成应用崩溃或横屏通过。正式持久权限仍由用户申请；验证包的读写/重启成功不代表生产获批。权限与 SDK 下限、包划分均未改变。
