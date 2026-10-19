# 手机与 2in1 文件回归 ST-DEVICES-001

基线 22cca7b。REQ-DEVICES-001：在手机模拟器与真实 2in1 上检查精简后的打开/取消、拖入/拒绝后重试、原位保存、另存目标切换、Markdown/HTML/ZIP 导出；落盘可访问时核对真实字节。不得把模拟器结果写成真实手机结果，不把注入 Want 当成系统文件授权。

沿用现有实现与单 HAP，只对实际发现的问题做最小修复；不增加架构层，所有手写文件不超过 500 行。仅升级 validation 包，测试自建样本，保留正式安装及用户数据。无行为修复时提交验证文档即可。

验证范围区分：系统选择器/文件管理器真实授权、可操作的跨应用拖入、编码与换行保留、保存/导出后复读、ZIP/HTML 内容核对。系统或模拟器不支持的交互明确记录，不能用单元测试冒充设备通过。

## 环境与范围

2026-10-19，Windows / DevEco Studio。初始工作区干净。两端安装相同的 `com.markdownworkbench.validation` HAP，正式包 `com.markdownworkbench.app` 未覆盖，未清除应用数据。本轮没有发现需要修复的应用问题，仅增加验收记录与证据，不增加生产代码、状态、抽象或分包。

| 设备 | 系统 | 显示 | 类型 |
| --- | --- | --- | --- |
| HAD-W32 / MateBook Pro | OpenHarmony 7.0.0.106 / API 26 | 3120×2080，窗口模式 | 真实 2in1 |
| Pura 90 | OpenHarmony 6.1.1.125 / API 24 | 1320×2856，竖屏 | 手机模拟器 |

经用户明确同意执行 `Emulator.exe -license accept`，启动已有 Pura 90 镜像；输入法首次设置选择基本模式。未开通输入法全量模式。测试样本通过 HDC 放入公共文档目录，再由实际系统选择器或文件管理器交给应用；没有注入 Want 或替换文件系统授权接口。

## 文件流程结果

| 流程 | 手机模拟器 | 真实 2in1 |
| --- | --- | --- |
| 系统选择器打开 | 打开 phone1720.md，中文及 emoji 正常 | 打开 pc1720.md，中文及 emoji 正常 |
| 取消 | 打开取消、另存为取消均保留 phone1730.md 和 46 字正文 | 另存为取消保留原文档，随后仍可另存 |
| 原位保存 | 追加 PHONE_SAVE_1729，原文件 51 字节 | 追加 PC_SAVE_1722，原文件 48 字节 |
| 编码与换行 | 原文件 UTF-8 BOM、CRLF 保留 | 原文件 UTF-8 BOM、CRLF 保留 |
| 另存后继续保存 | phone1730.md 追加 NEW_PHONE_1734，60 字节；原文件仍 51 字节 | pc1726.md 追加 NEW_PC_1727，54 字节；原文件仍 48 字节 |
| Markdown 副本 | Documents/phone1730.md，与当前文件逐字节相同 | copy1731.md，与当前文件逐字节相同 |
| ZIP | phone1730.zip 的 document.md 与当前文件相同，CRC 通过 | pc1726.zip 的 document.md 与当前文件相同，CRC 通过 |
| HTML | phone1730.html 含最新标记 | pc1726.html 含最新标记 |
| 跨应用拖入 | 未完成，见下文限制 | 真实文件管理器拖入 HTML 被明确拒绝，紧接着拖入 Markdown 成功，无卡死 |
| 应用重启后重开 | force-stop 后启动，从最近打开 phone1730.md，46 字及最新内容保留，无需重新选择文件 | 本轮未新增重启测试 |

两端另存得到的新文件均为 UTF-8 无 BOM / LF；原文件保留 BOM / CRLF。导出保持当前保存目标，副本与另存后再次保存的目标内容一致。以上不是仅凭按钮提示判断：实际从设备取回文件，比较长度、字节、ZIP CRC 和正文标记。

2in1 拖入样本 drop1733.md 导入为应用内文档 `library/drop1733.md`，33 字节与来源完全相同；非法 HTML 后没有重启应用，立即继续成功导入。截图：[拒绝 HTML](../ux/phone-pc-regression/pc-rejected-drop.jpg)、[随后导入 Markdown](../ux/phone-pc-regression/pc-imported-drop.jpg)。

2in1 另用包含本地 PNG 引用的应用内 export1739.md 导出 ZIP 和 HTML：ZIP 包含 document.md 与 attachments/rg1739.png，PNG 字节一致；HTML 内嵌 PNG 解码后字节一致，正文含 FRESH_1739。编辑器正文换行规范化为 LF，ZIP 正文与规范化后的输入一致。[图片文档截图](../ux/phone-pc-regression/pc-image-document.jpg)。手机本轮仅验证纯文字导出，未新增带图片导出测试。

[手机重启后重开截图](../ux/phone-pc-regression/phone-reopened.jpg)。[证据清单](../ux/phone-pc-regression/evidence.json)记录验证 HAP 的 SHA-256、样本/产物长度与 SHA-256、20 项字节检查结果以及四张截图源文件名和等比缩放尺寸。样本与辅助脚本保留在忽略目录 `build-logs/device-regression/`，设备上的有效测试文件保留便于复查；误用 HDC 相对源路径产生的五个空壳样本目录已逐项清理，仅删除本任务创建的文件和空目录。

## 可复现检查

设备命令示例（`<device>` 为上述设备，`<absolute-output>` 为本机绝对输出路径）：

```text
hdc -t <device> file recv <public-docs>/phone1730.md <absolute-output>
hdc -t 3QC0124C11000711 shell uinput -M -g 2044 1196 1130 1000 1800
hdc -t 3QC0124C11000711 shell uinput -M -g 2050 869 1130 1000 1800
hdc -t 127.0.0.1:5555 shell aa force-stop com.markdownworkbench.validation
python build-logs/device-regression/verify_evidence.py
```

拖入命令对应本轮窗口位置，需要先把文件管理器置前，不能直接复用到其他窗口布局。2in1 公共文档目录为 `/data/service/el2/100/hmdfs/account/files/Docs`；模拟器为 `/storage/media/100/local/files/Docs`。辅助检查输出为 `20/20 device file checks passed; 4 captures`。

本轮再次运行：

- `node scripts/test-host.cjs`：237/237。
- `node scripts/test-editor-actions.cjs`：24 组。
- `node scripts/test-file-transactions.cjs`：14 组。
- `node scripts/test-page-viewmodels.cjs`：7 组。
- `node scripts/test-external-access.cjs`：9 组。
- `node scripts/test-window-viewport.cjs`：8 组。

上述主机测试使用真实业务模块，但平台边界为 mock，不代替设备授权验证。本轮未改源码，沿用基线已通过的 ArkTS test / Release HAP 构建及同一验证 HAP，不重复签名构建。

提交前 `node scripts/check-source-size.mjs`、`node scripts/check-source-encoding.mjs`、`node scripts/check-docs.mjs`、`git diff --check` 均通过：122 个手写源码/测试/脚本符合 500 行限制，197 个文本文件通过严格 UTF-8 检查，42 个 Markdown 文件通过编码与本地链接检查。中文按 UTF-8 回读正常，截图已逐张检查。

## 限制与回滚

手机模拟器已尝试多任务手势、切换木笺卡片及图标点击/长按，没有找到可供本次操作的分屏/悬浮拖入入口；长按进入应用信息。手机真实跨应用文件拖入仍未验收，不推断系统不支持，也不把 2in1 通过当作手机通过。真实手机、物理设备重启、云盘提供方、手机横屏、未保存内容下的拖入取消、本轮的文件管理器“打开方式”冷启动均未重新覆盖；既往记录不替代本轮结果。

无生产行为变更；回滚只需回退本次文档提交。样本均为本任务创建，正式安装及用户文档未修改。
