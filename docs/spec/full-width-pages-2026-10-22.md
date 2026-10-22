# 宽屏页面与品牌图标修正 ST-LAYOUT-005

## 后续：首页新建入口对齐 ST-LAYOUT-008

REQ-LAYOUT-008：用户要求首页“新建文档”移至右侧末端，与下方组件右缘齐平。移除 HomeWelcome 标题行额外的窗口按钮宽度占位；改用已有 titleControlsBottom 在顶部避让窗口控制区，保持按钮与文档列表共用左右留白。复用系统窗口数据，不新增业务状态或抽象，不修改文档和手机首页结构。回退该改动只恢复按钮位置。验证调试构建、PC 对齐与窗口按钮无重叠、点击入口、源码大小/编码/文档检查。

2026-10-22 验证：原签名调试副本 `hvigorw.bat assembleHap --mode module -p product=default --no-daemon` 成功，33 项任务，日志 `build-logs/quality30-build.log`；MateBook Pro API 26 `hdc install -r` 成功。2090×1394 窗口截图 `build-logs/quality30-pc-home.png` 已打开，确认按钮在主区最右端并与下方文档卡片齐平，位于系统窗口按钮下方。点击“新建文档”进入空白编辑器，未输入或保存，返回后既有文档与 1 份恢复草稿保留。未重做手机、平板或各窗口尺寸回归；手机独立首页组件未修改。本次为展示位置调整，不新增业务测试；提交前检查源码 500 行、UTF-8、文档链接与 diff。

REQ-LAYOUT-005：设置页横向使用窗口可用宽度；“我的文档”使用剩余高度并可滚动访问全部文件；首页品牌图标与应用图标共用完整分层资源。保留手机安全区域、文档、偏好及现有文件操作，不增加抽象或权限，手写文件不超过 500 行。

代码事实：SettingsPage 将内容限制为 680vp；HomeLibraryPanel 内层 Scroll 限高 200vp，首页调用方又包裹 Scroll；HomeNavigation 只引用透明 foreground。设计：移除设置最大宽度；文档区改为单层 List，标题固定、列表占剩余高度；首页以当前 SDK 的 ResourceManager.getDrawableDescriptor 取得 app/ability 同用的 layered_image 完整图标，不另造位图。

验收：构建通过；PC 设置组占可用宽度，我的文档末尾可滚动到达、文件名左对齐；PC 图标完整背景和前景一致；手机模拟器检查设置与列表不溢出。仅修改展示，回退提交不涉及数据迁移。

## 验证记录（2026-10-22）

- 当前 SDK `@ohos.resourceManager.d.ts` 的 `getDrawableDescriptor(resId: number, ...)` 自 API 10 提供，满足项目 API 24 基线。复用既有分层资源，未新增图片文件或状态。
- `node scripts/test/test-page-viewmodels.cjs`：7 组通过，包含设置串行写入、生命周期及恢复草稿保护。
- 本地原有签名副本执行 `hvigorw.bat assembleHap --mode module -p product=default --no-daemon`，33 项任务构建成功；日志 `build-logs/quality27-build.log`。API 26 MateBook Pro 和 API 24 Pura 90 手机模拟器均以 `hdc install -r` 覆盖安装成功，未清空数据、修改偏好或文档。
- PC 窗口 2090×1394：设置页主题起点从旧居中区域 x1057 移至 x658，右侧开关到 x2620；主题选项由旧每项 381 像素扩大为 647 像素。“我的文档”9 个文件从第一项到最后一项均可见，文件名左对齐且横向占据主区；单层 List 不再受 200vp 高度限制。此次 9 项均能容纳，无需滚动，不将此记为超长列表压力测试。
- PC 首页图标经截图确认包含蓝色背景、白色文档与笔，使用与 app/ability 图标同一个 layered_image。最终截图已打开核验：`build-logs/quality27-pc-library-final.png`、`build-logs/quality27-pc-settings-confirm.png`；中途被其他应用遮挡的截图未用于验收。
- 手机模拟器 1320×2856：设置按钮和开关未横向溢出，原有 1 份文档可见，底部导航仍在安全区内；已查看设置截图 `build-logs/quality27-phone-settings.jpeg`。未执行删除或修改偏好。
- 提交前检查：源码 500 行限制、严格 UTF-8、Markdown 本地链接和 `git diff --check`。本轮未新增 SDK 单测或重做正式 release 签名；变化限于布局与已有资源展示。
