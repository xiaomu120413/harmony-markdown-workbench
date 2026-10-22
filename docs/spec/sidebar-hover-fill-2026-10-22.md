# 侧栏文件整行悬停 ST-LAYOUT-007

REQ-LAYOUT-007：编辑侧栏最近/资料库文件行悬停底色填满整行，左侧不再留未填充条带；保持文字缩进、完整文件名提示及打开/置顶/删除的独立原生按钮。用户已确认指“悬停时整行的底色没铺满左边”。

代码原因：DocumentSidebar 外层横向 padding 为 6vp，文件入口按钮单独高亮，置顶和删除区域不参与整行底色。修改为外层无横向 padding，把相同缩进移入标题、搜索和文件内容。实机确认 Row 的 hoverEffect 不能产生所需整行底色，而 StateStyles.hovered 为 API 26 新增，不适用于 API 24 基线；最终只增加一个组件内 hoveredDocId 表示当前悬停行，由原生 onHover 驱动背景色，不进入 ViewModel/持久化，不建包装组件。回退提交只影响展示。

验收：PC 鼠标悬停时底色从侧栏左缘延伸至操作按钮区域，移出恢复；文字、菜单及原生文件名提示保留。执行调试构建、500 行、UTF-8、文档及 diff 检查，不操作文档正文和删除动作。

## 验证结果（2026-10-22）

API 26 MateBook Pro HAD-W32，窗口 2090×1394：覆盖安装最终调试包后，打开已有 `MuMark PC quality check.md`，未修改正文。用设备 `uinput -M -m x y -i 800` 悬停最近列表第一项：整行底色覆盖从侧栏左边缘到删除按钮右缘，完整文件名原生提示仍出现；移动到删除按钮仅触发悬停，行底色保持，按钮自身热区独立；移到工具栏 400ms 后整行与按钮底色恢复。

最终截图已打开逐张检查：本地忽略目录 `build-logs/quality29-full-row-detail.png`、`quality29-action-hover-detail.png`、`quality29-dismiss-detail.png`。之前仅尝试原生 Row 高亮/样式的截图不作为最终通过证据。

本地既有签名副本执行 `hvigorw.bat assembleHap --mode module -p product=default --no-daemon` 成功，33 项任务，日志 `build-logs/quality29-build.log`；`hdc install -r` 成功，未卸载或清空数据。本轮只改一个显示组件，没有新业务逻辑测试；没有重做手机/平板或深色悬停验收、正式 release 签名。

提交检查通过：`node scripts/check/check-source-size.mjs`（132 个手写文件不超过 500 行）、`node scripts/check/check-source-encoding.mjs`（256 个文本）、`node scripts/check/check-docs.mjs` 和 `git diff --check`。文档及恢复草稿不做修改。
