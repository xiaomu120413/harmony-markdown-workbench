# HTML 只读预览 ST-HTML-001

REQ-HTML-001：用户可拖入或选择 .html / .htm，查看排版内容；HTML 不是 Markdown 编辑会话，不提供保存或自动保存。原 Markdown 文档和草稿保持独立，返回可继续编辑。

REQ-HTML-002：使用独立 Web 实例，禁用 JavaScript、文件访问、网络与页面跳转，不注册 JSBridge。CSP 禁止脚本、子框架、表单、外部资源，仅允许内联样式及 data 图片；不承诺运行网页应用或读取同目录资源。无需新增权限、依赖或分包。

设计：DocumentIntake 负责扩展名与目标页面；沿用现有拖入副本、UTF-8/大小检查及系统选择器。HTML 预览 ViewModel 负责读取与只读 Web 装载，页面只展示状态及返回操作。编辑器收到 HTML 时 push 预览路由，保留当前编辑会话；资料库和最近记录统一按扩展名分流。文件仍不超过 500 行，不增加通用框架。

依据：当前 SDK web.d.ts 的 javaScriptAccess / fileAccess / blockNetwork，以及 WebviewController.loadData。官方 [Web 属性文档](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-arkweb/arkts-basic-components-web-attributes.md)。

验证计划：入口分流、非法类型拒绝、CSP 和只读配置、读取失败与过期回包测试；ArkTS test / HAP；真实 2in1 HTML 拖入显示、恶意脚本不执行、返回 Markdown、手机模拟器选择 HTML。既往 ST-DEVICES-001 的拒绝 HTML 为当时行为，本需求从此改变该行为。回滚为回退本次提交，已导入 HTML 副本保留，不修改源文件。

## 验证记录

2026-10-19，Windows / 当前 DevEco SDK（API 26，最低 API 22）。HAD-W32 / MateBook Pro 为真实 2in1，OpenHarmony 7.0.0.106 / API 26；Pura 90 为手机模拟器，OpenHarmony 6.1.1.125 / API 24。仅升级 validation 包，正式安装和用户文件未改动。

- 2in1 实际从文件管理器拖入 no1733.html，显示绿色 HTML_SAFE_1754、表格 A/B 和绿色内嵌 PNG。脚本试图改写正文为 SCRIPT_EXECUTED，图片 onerror 试图改写为 123，均未生效。外链图片与 iframe 不加载；点击 BLOCKED_LINK 后仍停留当前预览。拖入导入副本为 613 字节，取回后与原样本逐字节相同。
- 首次设备回归发现空白页，调整为初始 Web 页面完成后装载文档，并只允许初始空白页/预览虚拟地址通过 URL 拦截；后续 onPageEnd 不再次装载，防止循环。修正后的最终 HAP 已在两端重新安装并复测 HTML 显示。
- 2in1 从 pc1726.md 拖入 HTML，返回后仍为 pc1726.md、40 字、已保存；取回 Markdown 文件仍是原先 54 字节，逐字节不变。预览没有保存按钮和自动保存协调器。
- 手机实际经系统选择器“浏览 → 我的手机 → a1754.html”打开同一 HTML 样本，窄屏标题、状态、安全区域和正文显示正常；最终包升级后从最近记录再次打开也正常。取回外部 HTML 仍与 613 字节原样本一致。
- 同一 HTML 再次拖入复用已有相同副本，未产生额外副本；资料库与最近记录按扩展名打开 HTML 预览。重命名补全原 HTML 扩展名，不再误加 .md，主机测试覆盖 .html 保留和显式改为 .htm。

[2in1 最终预览](../ux/html-preview/pc-preview.jpg)、[手机最终预览](../ux/html-preview/phone-preview.jpg)、[返回 Markdown](../ux/html-preview/pc-returned.jpg)。[证据清单](../ux/html-preview/evidence.json)记录原始截图、裁剪/等比缩放、样本及验证 HAP 哈希。截图不包含重新绘制的界面。

命令及结果：

- `node scripts/test/test-html-preview.cjs`：8 组通过，覆盖路由/HTML 重命名、读取与 Web 装载先后、重复页面完成事件、CSP、无效 UTF-8、大小限制、读取失败和销毁后回包。平台读写 mock；Web 禁用配置通过源码检查，真实渲染以上述设备结果为准。
- 原主机回归 `test-host.cjs`、`test-editor-actions.cjs`、`test-file-transactions.cjs`、`test-page-viewmodels.cjs`、`test-external-access.cjs`、`test-window-viewport.cjs`：237/237、24、14、7、9、8 组通过。
- `hvigorw.bat test --mode module -p product=default` 与 `hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release`：BUILD SUCCESSFUL；日志位于忽略目录 build-logs/html-test.log、html-release.log，既有 ESObject/弃用警告保留。
- HDC `file recv` 分别取回应用内 HTML、原 Markdown、手机外部 HTML；与本机样本比较，html_copy_exact、markdown_unchanged、phone_html_unchanged 均为 True。样本及脚本在 build-logs/device-regression/。
- 源码 500 行、严格 UTF-8、文档链接和 `git diff --check` 在提交前通过。没有新增权限、三方依赖、通用封装或分包。

未验证：真实手机、手机跨应用拖入、HTML 的文件管理器“打开方式”真实授权冷启动、全类型网页与所有编码。外部 HTML 原文件只读取，非 UTF-8 和超过 8 MB 文件明确报错；相邻资源文件不加载。HTML 预览保留文档自身颜色，不强制修改其 CSS 以适配应用深色主题。
