# 新版手机与平板 UI 回归 ST-MOBILE-UI-001

REQ-MOBILE-UI-001：回归新版设置、我的文档与按钮对齐；手机允许模拟器，能测的平板真机进行验收，问题直接修复，手写文件不超过 500 行，验证后提交推送。保留已有文档与偏好，不增加封装或权限。

基线 a7c03e5。检查设置浅深主题、等宽选项、字体与视图操作、帮助展开和滚动；我的文档使用剩余空间、长名称及超过一屏的列表滚动、菜单和打开；手机竖横屏及软键盘下按钮、安全区与内容可达。仅使用本轮独立测试文件，结束恢复设置与旋转锁定，删除测试文件。

环境：Pura 90 模拟器 API 24 / OpenHarmony 6.1.1.125，1320×2856。连接的 MatePad Pro PCE-W30 为 API 22 / OpenHarmony 6.0.2.130，低于当前 compatibleSdkVersion 6.1.1(24)；用户确认无 API 24 平板，要求平板未测项如实记录。不降低项目基线、不安装历史包充当新版验收。本机 MatePad Pro 13 模拟器启动亦被 SDK 协议未确认拦截，本轮不将其记为已测环境。

## 已验证结果

| 场景 | 证据与结论 |
|---|---|
| 安装 | 当前 a7c03e5 对应原调试签名包在手机以 `hdc install -r` 覆盖成功；没有卸载或清数据 |
| 竖屏设置 | 主题三项各 345×154 像素，默认视图三项各 341×154 像素；字号与开关在组内，无横向溢出 |
| 设置滚动 | 深色主题、帮助展开、全部帮助与快捷键滚动到底通过；最终快捷键文字位于安全区内 |
| 竖屏我的文档 | 用应用创建 3 份独立 UI31 测试文档，总计 4 份。长文件名省略，更多菜单重命名/删除/取消入口正常，取消不改变文档；单层 List 使用剩余空间 |
| 横屏 | 实际窗口确认 2856×1320；首页切换两栏，完整应用图标可见，新建按钮位于文档区右端，与卡片齐平 |
| 横屏列表 | 第四项初始在视口底部部分可见，向上滚动后末项完整显示为 57 像素高且可达；头部仍保留在列表上方 |
| 横屏设置 | 主题三项各 808×154 像素，默认视图三项各 803×154 像素；全宽分组未超出安全区。字号从 15 增至 16，再恢复 15 |
| 默认视图 | 将设置改为预览，返回后打开 UI31 测试文档，只显示 preview Web，证明设置生效；主题已恢复跟随系统 |

本轮尝试直接注入测试文件被模拟器沙箱拒绝，没有改沙箱权限，改用应用实际创建测试文档。工具输入过程中会产生中文哨兵临时文本，一份测试文件名因此含“中”，属于自动化输入夹具；未据此报告产品乱码。模拟器控制中心动画期间的滑动超时与字段查找/输入校验超时，均以之后的真实 UI/文件结果核验，不伪装为应用崩溃。

截图已打开核验：`build-logs/quality31-phone-help-dark.jpeg`、`quality31-phone-library-dark.jpeg`、`quality31-phone-landscape-library.jpeg`、`quality31-phone-landscape-settings.jpeg`。名为 `quality31-phone-landscape-keyboard.jpeg` 的截图实际没有软键盘，不能作为键盘验收证据；后续模拟器被木络切走，追加键盘验收中断，被遮挡/切走截图不作为木笺通过证据。

## 最终补验与环境恢复

用户随后允许模拟器仅用于木笺，追加软键盘验收完成：横屏点击编辑工具栏“查找”后，查找 TextInput 获焦，格式工具栏收起，正文 Web 剩余 89 像素可见区域；关闭查找、收起键盘后布局恢复。已打开实际带键盘截图 `build-logs/quality31-phone-landscape-ime-verified.jpeg` 核验。此前被其他任务切走期间的 Ctrl+F 发送和焦点观察不记为通过，也不能归因于木笺缺陷。

本轮未发现新的设置、我的文档或按钮对齐缺陷，因此不修改运行时代码、不增加封装。设置与 ViewModel 仍沿用基线实现；本次提交仅更新回归记录和索引。

- 最终恢复：主题跟随系统、字号 15、默认视图编辑；返回竖屏 1320×2856，控制中心旋转锁定恢复开启（蓝色图标，截图 `quality31-rotation-restored-tile.png`）。未修改自动保存、换行或行号开关。原文档最终打开为编辑 Web，证明默认视图恢复生效。
- 应用内创建的 3 份 UI31 文档均通过“我的文档→更多→删除→确认”清理，原目录仅剩既有 `木笺 L1 L2 自测.md`；临时传输目录中的 24 份未成功导入夹具亦已清理。测试输入哨兵和工具坐标必须为整数导致的校验重试不作为应用缺陷。
- 既有文档前后均 89 字节，SHA-256 一致：`07CEDE04E18807170C7040E8981EE2C50C6038BF9AE969BFF8F5CCB9B30E1BF1`，取回文件为本地 `quality31-original-before.md` / `quality31-original-after.md`。
- 当前签名副本与仓库所有已跟踪运行文件，在 CRLF/LF 归一化后逐一内容一致；部分原始哈希仅因换行差异不同。复用 `quality30-build.log` 对应构建成功的 HAP，没有在源码不变时重复构建，也未重新签正式 release。
- `node scripts/test/test-page-viewmodels.cjs`：7 组通过；`node scripts/test/test-window-viewport.cjs`：8 组通过。提交前 `node scripts/check/check-source-size.mjs`（132 个手写文件）、`node scripts/check/check-source-encoding.mjs`、`node scripts/check/check-docs.mjs`、`git diff --check` 通过。

平板结果仍为未测：现有真机 API 22 不满足 API 24 最低要求，用户已选择如实记录。本轮的手机横屏是手机模拟器验收，不等同于平板验收；不声称 API 22 支持、新平板通过或完整 L1/L2 认证。

## 追加平板界面探索 ST-TABLET-UI-002

用户随后要求“不影响，先看看”。设备当前无 com.mumark.app 或其他木笺包可供打开，因此在仓库外建立独立签名副本，使用当前 UI 源码，仅将临时包 compatibleSdkVersion 改为 6.0.2(22)，目标 API 仍为 24；正式仓库及发布包最低 API 24 保持不变。沿用已有调试证书/Profile，不创建新证书、不修改设备权限。该实验用于观察设置、我的文档、按钮对齐；不能替代 API 24 正式包平板回归，也不承诺 API 22 右键等已删除降级路径可用。构建/安装失败则记录实际阻断原因。

独立目录为 `C:/Users/mu/Desktop/code/local-sign/mumark-tablet-ui22-20261022`。`assembleHap --mode module -p product=default --no-daemon` 构建成功，34 项任务；日志 `build-logs/quality32-tablet-ui22-build.log`。已有签名 `hdc install -r` 安装成功，首次启动出现系统隐私服务提示。检查签名 HAP 内 module.json：com.mumark.app / 1.0.0，minAPIVersion=60002022、targetAPIVersion=60101024；仓库配置仍为二者 6.1.1(24)。逐一比较 entry/src/main 与 AppScope 的已跟踪文件，按 CRLF/LF 归一化后与临时副本完全一致。

初次启动的首页布局树可见，但后续平板被木络任务切走；当时设置页和字号操作未成功，不计为通过。首次名为 `quality32-tablet-settings-portrait.jpeg` 的截图实际为木络，不作为木笺证据。

用户随后表示“平板稍微晚点，好了我跟你说”，因此停止设备操作，等待用户通知。临时包保留供后续验收；尚未完成的设置、文档列表与横竖屏检查仍为待验收，不宣称整轮平板通过。无既有木笺安装或文档被卸载、替换或删除。

## 平板恢复验收结果（2026-10-22）

用户通知“开始吧”，随后实体旋转并回复“转了”。在同一 MatePad Pro API 22 上继续 UI 探索，竖屏 1920×2880、横屏 2880×1920，未修改正式最低 API 24。

发现临时降级包进入编辑器时退出：日志 TypeError / undefined is not callable，定位 `WebDragStyle.ets:6` 的 `web.enableDefaultContextMenu(true)`。这是临时包运行于低版本系统的接口缺失。仅在仓库外的验收副本中为该调用增加 `typeof web.enableDefaultContextMenu === 'function'` 检查；正式源码不增加已移除的低版本分支。此后的临时包与正式源码除最低版本配置外，另有这一个菜单调用检查差异，不再称运行文件完全一致。

临时副本再次执行 `assembleHap --mode module -p product=default --no-daemon`：33 项任务，BUILD SUCCESSFUL，日志 `build-logs/quality33-tablet-ui22-build.log`。沿用原签名覆盖安装成功，没有卸载、清数据或创建第二个木笺。随后编辑器正常进入并跨旋转保持可用。

| 场景 | 现场结论 |
|---|---|
| 竖屏设置 | 分组铺满可用宽度；主题三项各 573×88 像素、视图三项各 571×88 像素；字号 15→16→15 生效 |
| 深色与帮助 | 深色主题生效，展开帮助并滚动到 Ctrl+Z/Y，末项在安全区内；之后恢复跟随系统 |
| 横屏设置 | 分组宽 2816 像素，主题三项各 905×88、视图三项各 903×88；开关和字号按钮未溢出 |
| 横屏我的文档 | 单层 List 为 2295×1346 像素，使用剩余高度；新建按钮右边界 2816，与主内容区一致；侧栏完整图标可见 |
| 默认视图 | 选择预览后从我的文档打开 yy.md，实际 Web 为 preview.html；切回编辑显示 editor.html，正文仍为 yy 加换行 |
| 横屏软键盘 | 展开查找后软键盘出现，正文 Web 仍有 592 像素高度，保存与查找操作在键盘上方；关闭查找返回后布局恢复 |
| 文档菜单 | yy.md 的菜单显示重命名、删除、取消；选择取消后文档仍在，未执行删除或改名 |

已打开核验截图：`build-logs/quality33-tablet-settings-portrait.jpeg`、`quality33-tablet-help-dark.jpeg`、`quality33-tablet-settings-landscape.jpeg`、`quality33-tablet-library-landscape.jpeg`、`quality33-tablet-ime-landscape.jpeg`。

本次恢复操作时已有用户文档 yy.md，按已有文档保留，未写入正文、改名或删除；没有创建新测试文件。最终恢复跟随系统、字号 15、默认编辑，自动保存/换行/行号保持原值，设备保留用户当前横屏，应用停在我的文档。未发现这几项布局的新缺陷，因此正式仓库只更新记录与索引，不增加运行时封装。

边界：平板只有一个文档，未验证平板超一屏列表滚动和长文件名；本轮不覆盖实际删除、文件拖入或系统原生右键。手机相应结果见上文。API 22 临时界面探索不能替代 API 24 正式包平板回归，API 24 平板仍缺少设备，不声称完整平板兼容或 L1/L2 认证通过。

当前 SDK 的 `openharmony/ets/component/web.d.ts:8100` 对 enableDefaultContextMenu 标记 `@since 24`，与现场 API 22 缺失一致。提交前运行 `node scripts/check/check-docs.mjs`（76 个 Markdown）、`node scripts/check/check-source-size.mjs`（132 个手写文件）、`node scripts/check/check-source-encoding.mjs`（257 个文本文件）、`git diff --check` 均通过。本次正式仓库只有文档更新，不重复构建正式 HAP；临时 HAP 构建结果如上。
