# web/ 层

ArkWeb 编辑运行时资源说明（SDD 7.2 / ADR-001、ADR-005）。本目录只放说明，**没有手写运行时源码**。

实际源码与构建链：

- `web-tools/src/editor.js`：CodeMirror 6 编辑封装、快捷键与桥消息（M2-01 / M2-02）。
- `web-tools/src/preview.js`：预览宿主 `window.__previewApi`。
- `web-tools/src/markdown.js`：markdown-it（表格/任务列表/脚注/高亮）+ 沙箱 HTML 内容块。
- `web-tools/src/html-embed.js`：HTML 内容块提取、资源打包与离线化。
- `web-tools/build-web.js`：esbuild 打包为 `entry/src/main/resources/rawfile/web/editor.bundle.js`、`preview.bundle.js` 与 `editor.html`。

约束（SDD 6.3、7.3）：

- 所有 JS/CSS/字体本地打包，离线可用；禁止远程资源。
- Markdown 渲染 `html: false`（原始 HTML 标签不执行），并依赖 markdown-it 默认链接协议校验拒绝 `javascript:` 等危险协议。
- HTML 内容块以 `data:text/html;base64` + `sandbox=""` iframe 隔离渲染；HTML 只读预览另由 `domain/preview/HtmlSafety` 做危险标签检测。
- 未引入 DOMPurify（依赖未入仓）；如后续引入，须固定版本并同步 NOTICE。
- 依赖锁定在 `web-tools/package-lock.json`；修改 Web 源码后必须运行 `node web-tools/build-web.js` 并提交产物，CI 会校验 bundle 一致性。
