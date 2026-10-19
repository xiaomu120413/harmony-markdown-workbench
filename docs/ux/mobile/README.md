# 手机/平板布局验证截图

这些是 API 26 MateBook Pro 的真实自由窗口截图，**不是手机或平板硬件截图**。比例和裁剪坐标见 [captures.json](captures.json)。仅裁掉窗口外内容，宽图缩到 1200px，未修饰应用内容。

| 文件 | 检查内容 |
|---|---|
| [宽窗编辑](01-editor-wide.jpg) | 原生输入 69 字符，正文区占满可用高度 |
| [中窗编辑](02-editor-tablet.jpg) | 保存成功、约702vp窗口 |
| [窄窗编辑](03-editor-phone.jpg) | 约363vp，正文保持与自动换行 |
| [低高度查找](04-find-low-height.jpg) | 辅助栏收起、查找限高可滚动、正文仍可见 |
| [底部文件操作](05-file-sheet.jpg) | 窄窗 sheet、位置和保存状态 |
| [最终两栏首页](06-home-tablet.jpg) | 计数避让系统三键 |
| [最终窄窗设置](07-settings-phone.jpg) | 默认视图说明与选项分行 |
| [最终低高度首页](08-home-low-height.jpg) | 打开、搜索与导航仍可达 |
| [最终低高度资料库](09-library-low-height.jpg) | 资料库独立滚动 |

前五张属于本轮修正与回归过程，后四张属于最终验证安装。后续只清理无引用常量，未改变这些界面的行为。安全区/键盘的实现、已测范围和未验证项见[验收记录](../../spec/mobile-adaptation-2026-10.md)。
