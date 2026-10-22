# 文档入口精简与图片预览核验 ST-IMAGE-001

REQ-IMAGE-001：移除文档编辑工具栏及文档操作面板中的设置入口，设置统一从首页进入；删除失去调用方的方法，不增加封装。核验用户当前图片及正常尺寸图片的预览、视图切换，保留原文档和未保存草稿。手写文件不超过 500 行。

当前证据：PC 文档引用 `mumark-drop-20261020(5).png`，应用附件原文件为 70 字节，取回后 Pillow 确认为 1×1 RGBA；UI 树显示两张图片各约 3×3 设备像素。不能仅凭该现象认定图片加载失败，也不应强制放大全部图片。使用独立正常尺寸图片文档继续检查。

实现范围：精简 EditorCommandBar、EditorFileActions 与 EditorController 中设置入口及对应旧测试。图片链路若能复现故障，再按证据修复。回退提交可恢复入口，不迁移文档或偏好，不新增权限。

验证计划：编辑操作宿主回归、必要图片链路回归、调试 HAP 构建与 PC 真机核验，UTF-8、文档链接、500 行限制及 diff 检查。安装前保留当前未保存内容为恢复草稿，不覆盖原文件。

## 验证结果

2026-10-22，API 26 MateBook Pro HAD-W32 实机：先在已有离开确认框选择“保留草稿离开”，确认首页有 1 份恢复草稿，再用原有调试签名覆盖安装，未卸载或清空数据。独立测试文档引用新建的 960×540 PNG 和当前 1×1 PNG；前者在分屏显示为 735×414 设备像素、独立预览显示为 1499×844，后者仍为约 3×3。预览→编辑→分屏切换后正常图片继续显示，截取应用窗口并打开核验，证据为本地忽略目录 `build-logs/quality26-pc-image-final.png`。本轮没有复现图片加载故障，因此没有臆测修改图片加载逻辑，也没有强制放大小图片。

最终 PC 编辑工具条未出现设置按钮；窄屏文档操作面板的设置入口也已从源码移除。独立测试文档验收后由应用确认删除，新建测试附件随后清理；用户原图片、文档及恢复草稿保留。正式 release、手机新包验收和网络图片未包含在本轮。

通过命令：`node scripts/test/test-editor-actions.cjs`、`node scripts/test/test-html-embed.cjs`（13 组）、`node scripts/test/test-html-resources.cjs`（10 组）。本地既有签名副本执行 `hvigorw.bat assembleHap --mode module -p product=default --no-daemon` 成功，33 项任务，日志 `build-logs/quality26-build.log`；PC `hdc install -r` 成功。提交前执行源码 500 行限制、严格 UTF-8、文档链接和 `git diff --check` 检查。
