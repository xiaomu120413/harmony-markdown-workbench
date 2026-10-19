# 文档操作入口与窄屏面板

2026-10-19。TASK-ACTIONS-001，承接[文件入口验收](file-intake-verification.md)。

## 问题、范围与验收

现有“文件”与其他工具同为灰色块，菜单把导出格式全部摊开，缺少手机专用交互。只完成桌面菜单验收，不能声称手机体验已通过。

| 需求 | 验收 |
|---|---|
| FR-ACTIONS-001 | 宽窗使用系统图标和轻量文档入口；菜单保留新建、打开、另存，导出和复制使用下一层，缩短首层列表 |
| FR-ACTIONS-002 | <600vp 使用紧凑标题栏及底部可滚动操作面板；展示当前文档与保存位置；导出/复制分层，可返回或关闭，不显示桌面长菜单 |
| FR-ACTIONS-003 | 面板关闭后再执行系统选择器或文档切换；取消、返回、变窄变宽不修改正文；暗色、长文件名和短窗不裁切关键操作 |
| FR-ACTIONS-004 | 保持零新增权限。当前打开/另存通过系统选择器授权，拖入通过系统交付导入副本；不因菜单调整申请公共目录权限 |

非目标：全应用重设计、目录工作区、公共目录扫描、正式签名迁移及手机全量认证。

## 设计与依据

- 宽窗菜单、窄窗 bindSheet 使用现有 ArkUI 和主题；系统 SymbolGlyph，不制作一套新图标。
- 编辑页窄屏标题栏保留文档名、保存状态、保存和操作入口，编辑/预览、大纲及查找放第二行。窄屏隐藏内联文档侧栏，避免正文被挤窄；宽屏侧栏偏好保留。大纲也以面板展示，点击后关闭并跳转。
- 窄屏面板支持根操作、导出、复制分层；关闭生命周期触发实际动作，防止系统选择器被面板遮挡。短列表靠顶，长列表滚动；返回键先处理面板。
- EntryAbility 使用当前 SDK 的 getTitleButtonRect / windowTitleButtonRectChange 发布系统三键实际高度，窄窗保留可拖动区域避免遮挡；手机无三键时高度为零。[官方窗口避让示例](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-1089)。
- 设置加载和保存时同步应用 ColorMode，避免深色自绘页面上的原生菜单和系统三键仍采用浅色模式；属于 FR-ACTIONS-003 的主题可用性修复，失败记录日志。
- “3D”按 Desktop/Documents/Download 理解：当前操作无需整目录权限。长期目录工作区及兄弟图片读取需另做需求与授权设计，不能把它们包装为已支持。
- [官方公共目录权限](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-v5/permissions-for-all-V5)说明相应公共目录权限仅 2in1 可申请；[官方 bindSheet 指引](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-1033)说明半模态行为。实际参数以本机 SDK component/common.d.ts、symbolglyph.d.ts 为准。

## 实施、验证与回滚

单一任务 TASK-ACTIONS-001，主要修改 EditorPage 的操作展示，沿用现有保存/交付服务。低风险视觉修改不添加镜像测试；运行现有逻辑回归、文档检查、Debug/Release 构建及宽/窄窗真实操作。新增权限必须为零。可按提交回退 UI，不改变正文、草稿或元数据结构。

实际结果记录于[验收](document-actions-verification.md)。2in1 窄窗验收与手机实机验收必须分别标注。
