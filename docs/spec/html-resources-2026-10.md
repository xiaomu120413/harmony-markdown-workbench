# HTML 内嵌内容块 ST-HTML-002

REQ-HTML-003：在当前编辑器光标处插入 HTML，方式与本地图片一致；预览/分屏展示内容块，不切换文档或独立预览页。支持编辑器拖入和“插入 → HTML 内容块…”。同目录及子目录的 CSS、@import、普通图片及 CSS 背景图随 HTML 合成为离线附件；取消保留正文。首页/“打开文档”的单独 HTML 预览保持既有行为。

REQ-HTML-004：内容块只读且隔离，脚本、事件属性、原生桥、外部跳转、网络、表单和嵌套页面禁止。原文仍是 Markdown，使用 `![HTML]` 图片式扩展引用指向 attachments 下的 HTML 附件。独立 HTML 导出和图文 ZIP 都保留内容块及资源；普通 Markdown 导出仍提示不携带附件。

设计：复用 EditorDelivery 的附件插入、版本/会话检查、保存协调器和交付路径。HtmlResourceStore 负责白名单路径、系统已授权资源读取、单次插入的内存资源集合及限额。已有 UI 选择器提供临时目录或资源文件授权，资源齐全后只保存最终自包含附件，不保留目录长期授权、资源缓存目录或额外元数据。每次插入重新读取资源，避免沿用旧图片和 CSS。浏览器只接收数据附件，不直接访问原目录；拒绝路径越界、编码绕过及符号链接。

HTML 和 CSS 使用本地 htmlparser2 12.0.0 / css-tree 3.2.1 解析树处理，不用正则重写整个文档。采用解析器是为了正确处理实体、CSS 转义、嵌套引用与媒体条件，避免自行实现不完整解析器。固定依赖与传递依赖许可证已记录到 NOTICE，原文随 HAP 分发；没有新增权限、观察状态、通用抽象或分包。

资源先经系统授权导入，再在 Web 运行时合成：HTML 去除脚本、事件、表单行为和外部链接；CSS 与图片转内联/data URI；CSP 禁止脚本/网络并限制为内联样式、data 图片。最终渲染使用没有 allow-scripts、allow-same-origin 的 sandbox iframe，禁止访问父文档及 JSBridge。固定高度 420px，长内容在块内滚动，保持文档排版连续。直接 HTML 标签在普通 Markdown 中仍禁用。

限额：原 HTML 8 MiB，单资源 4 MiB，共 128 个 / 32 MiB；CSS 引用 16 层、解析累计 16 MiB、展开累计 12 MiB；HTML 节点 100000；最终自包含附件 12 MiB。超限/资源未齐/解析错误明确取消插入，不提交半成品正文。带 layer()/supports() 的 @import 条件暂不支持，普通 @media 条件已测试。

依据：[系统选择器](https://github.com/openharmony/docs/blob/master/en/application-dev/file-management/select-user-file.md)、[htmlparser2](https://github.com/fb55/htmlparser2)、[CSS Tree](https://github.com/csstree/csstree)及当前 SDK DocumentSelectMode.FOLDER。设备差异通过实际系统选择器验证，不把 HDC 推送样本等同于文件授权。

验收：主机验证资源图、路径/类型/额度/单次集合隔离、CSS 转义与循环、脚本过滤及 sandbox、光标插入/取消/过期回包；ArkTS test / Release；真实 2in1 拖入并内嵌显示、手机模拟器菜单插入和资源文件补齐、保存/重开与 ZIP/HTML 导出字节检查。文件仍不超过 500 行。

回滚：回退本次提交；已生成的 HTML 附件和 Markdown 引用不删除。其他阅读器可能将扩展引用显示为普通图片链接，ZIP 中的自包含 HTML 可单独打开。验证记录见下文。

## 验证记录

最终移除长期资源缓存后，再次安装同一验证包：2in1 通过系统 HTML 文件选择器和目录选择器重新插入，插入位置为当前文档开头；保存得到 189 字节，新插入引用之外的原 131 字节逐字节保持一致，新 HTML 附件与此前验证导出的附件完全一致。手机重新打开原文档，图片与 CSS 仍完整显示。补充 2/2 字节检查及[2in1 最终插入截图](../ux/html-insertion/pc-inline-fresh.jpg)、[手机最终重开截图](../ux/html-insertion/phone-inline-final.jpg)已记录到证据清单。资源测试覆盖单次集合隔离和重新插入读取新资源；不再保存资源缓存目录或文档 ID 元数据。

2026-10-19，Windows / 当前 DevEco SDK，最低兼容 API 22。初始工作区干净；仅升级 `com.markdownworkbench.validation`，正式安装和用户文件未覆盖。真实 2in1 为 HAD-W32 / MateBook Pro，OpenHarmony 7.0.0.106 / API 26；手机为 Pura 90 模拟器，OpenHarmony 6.1.1.125 / API 24。两端最终安装同一个验证 HAP。

- **编辑器拖入**：2in1 从真实文件管理器拖入本轮 HTML，原 pc1726.md 正文保留；光标位于末尾，HTML 引用插到正文后，文档未切换。预览中在原 Markdown 下方显示紫色标题、绿色普通图片和蓝色 CSS 背景。紫色标题来自第二层 @import。样本脚本和 onerror 尝试改写正文均未执行，外部链接已去除行为。
- **资源授权**：2in1 使用实际系统目录选择器补齐资源。手机通过“插入 → HTML 内容块…”选择 HTML，使用系统资源文件选择器依次补齐 main.css、nested.css、photo.png、background.png；本镜像实际每次选择返回一个文件，重复选择直到资源齐全。没有使用 HDC 代替授权；HDC 只放置自建样本和取回落盘文件。
- **保存及重开**：手机原位保存得到 119 字节 Markdown，原正文在插入引用之前；最终 HAP 升级后从最近重开，内容块仍完整。2in1 最终另存为 html-inline-2040.md，113 字节与此前导出快照一致；追加 AFTER_INLINE_SAVE 后继续保存得到 131 字节，保存目标仍为新文件。
- **离线副本**：2in1 临时将本任务创建的 mu1959 资源目录改名，force-stop 后重新启动，从最近打开已保存文档，普通图片和 CSS 背景仍显示；截图后恢复目录原名。最终内容块只读取 attachments 中的自包含 HTML，不依赖原资源目录。
- **取消插入**：手机最终包再次打开 HTML 插入选择器并取消，仍为 phone1730.md / 105 个 UI 字符，落盘 Markdown 与取消前 119 字节逐字节一致；没有额外插入引用。
- **ZIP**：真实系统保存 html-inline-2024.zip，1084 字节；CRC 通过，包含 document.md 和它实际引用的 HTML 附件。附件内的两张 PNG 解码后与源图逐字节相同，CSS 已展开，脚本和事件已去除。
- **独立 HTML**：真实系统保存 html-inline-2028.html，4108 字节；sandbox iframe 内的 base64 HTML 与 ZIP 附件完全相同，包含内联 CSS、普通图片及背景图。无 allow-scripts / allow-same-origin。

[2in1 移走源目录后重开](../ux/html-insertion/pc-inline-offline.jpg)、[手机内嵌效果](../ux/html-insertion/phone-inline.jpg)。[证据清单](../ux/html-insertion/evidence.json)包含最终 HAP 和产物哈希、17 项字节/结构检查、截图原始文件名、裁剪及缩放尺寸。没有重绘界面。

试验阶段的目录预览实现曾保留验证包的只读目录授权，影响旧外部样本写入。失败正文和 HTML 引用均保留在恢复草稿，已通过应用“另存副本”恢复到内部文档；试验目录策略已明确撤销，失败试验生成的零字节文件已核对后清理。最终实现只用临时授权合成附件，不保存/激活目录长期权限；清理代码不进入提交，正式安装不受影响。最终另存和后续保存已重新通过。

命令与结果：

- `node scripts/test/test-host.cjs`：237/237。
- `test-editor-actions.cjs`、`test-file-transactions.cjs`、`test-page-viewmodels.cjs`、`test-external-access.cjs`、`test-window-viewport.cjs`、`test-html-preview.cjs`：24、19、7、9、8、8 组通过。
- `node scripts/test/test-html-resources.cjs`、`node scripts/test/test-html-embed.cjs`：各 10 组通过。覆盖编码路径绕过、符号链接、资源限额、CSS 扩张限额、非 UTF-8 CSS、循环/@media/转义、单次集合隔离、资源合成及 sandbox。上述平台 IO 为 mock，设备授权以上述实测为准。
- `node web-tools/build-web.js`：两份 Web bundle 重新生成。htmlparser2 与 CSS Tree 固定版本，9 份直接/传递依赖许可证原文已确认包含在验证 HAP 中。
- `hvigorw.bat test --mode module -p product=default`、`hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release`：BUILD SUCCESSFUL。日志为 build-logs/html-insert-test.log、html-insert-release.log，既有 ESObject/弃用警告保留。验证包构建后再次构建正式包输出，配置仍为正式 bundleName。
- HDC `file recv` 取回 ZIP、HTML、Markdown；`python build-logs/device-regression/verify_inline_delivery.py`：17/17 通过。辅助脚本、原样本和完整输出保存在忽略目录。
- `check-source-size.mjs`、`check-source-encoding.mjs`、`check-docs.mjs`、`git diff --check` 在提交前通过；129 个手写源码/测试/脚本均不超过 500 行，没有增加观察字段、强刷计数器或通用架构层。

未验证：真实手机、API 22 设备、手机真实跨应用拖入、各种云盘提供方及任意网页完整兼容性。手机资源多选的实际体验受系统选择器限制，本轮按逐文件补齐验收。脚本、远端资源、非 UTF-8 CSS 和不支持的 @import 条件不参与动态网页还原；错误时不插入半成品块。
