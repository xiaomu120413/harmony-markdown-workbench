# 侧栏文件名提示与导航图标 ST-LAYOUT-006

REQ-LAYOUT-006：编辑页左侧最近/资料库中，悬停文件入口显示完整文件名；首页“我的文档”和“恢复草稿”图标体现文档集合与草稿历史。保持原点击、置顶、删除和键盘行为，不增加提示框状态或封装，手写文件不超过 500 行。

设计：在既有文件入口 Button 绑定原生 `bindTips(name)`，名称与现有 accessibilityText 使用相同来源；该能力由当前 SDK common.d.ts 标注 API 19 起提供，满足项目 API 24 基线。系统负责悬停延迟与收起。我的文档改用 `doc_plaintext_and_folder`，恢复草稿改用 `doc_text_badge_clock`，均在本地 SDK id_defined.json 中存在；最近文档仍使用 clock。

验收：调试 HAP 构建、PC 悬停完整长文件名以及移出收起，最近与资料库均覆盖，点击仍能打开文件；首页图标视觉确认；编解码、文档链接与 500 行检查。回退提交只恢复展示，不影响文档或偏好。

## 验证结果（2026-10-22）

API 26 MateBook Pro HAD-W32，应用窗口 2090×1394，沿用原调试签名覆盖安装成功。用设备自带 `uinput -M -m x y -i 950` 移动鼠标并等待原生提示：最近列表的省略文件名出现完整 `mumark-save-as-20261019.md`；资料库同名入口也出现完整名称，移至工具栏 400ms 后提示收起。单击资料库该入口，页头为完整同名文件且状态“已保存”；未编辑正文，返回首页后恢复草稿仍保留 1 份。

已打开截图检查：`build-logs/quality28-pc-hover-recent.png`、`quality28-library-confirmed.png`、`quality28-dismiss-confirmed.png`、`quality28-icon-confirm.png`。最近提示截图按应用边界裁剪导致浮出窗口部分被裁去，不据此判定系统提示文字截断；资料库确认截图保留了完整浮层。被其他应用遮挡的中间截图未用于验收。首页确认“最近”为时钟、“我的文档”为文件夹及文档、“恢复草稿”为文档及历史标记，三者可区分。

本地签名副本执行 `hvigorw.bat assembleHap --mode module -p product=default --no-daemon`，33 项任务成功，日志 `build-logs/quality28-build.log`。变更只有原生提示绑定与系统图标替换，不新增状态、封装或业务逻辑测试；以实际鼠标悬停验收。提交前运行源码行数、严格 UTF-8、Markdown 链接及 `git diff --check` 检查。本轮没有手机/平板真机悬停验收，也未重签正式 release。
