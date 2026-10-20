# web-tools/ — Web 编辑运行时源码与打包

ArkWeb 编辑运行时的**手写源码**在这里；`entry/src/main/ets/web/` 目录已移除，包资源在
`entry/src/main/resources/rawfile/web/`（由本目录的构建脚本生成，勿手改）。

- `src/editor.js`：CodeMirror 6 编辑封装、快捷键与桥消息（M2-01 / M2-02）。
- `src/preview.js`：预览宿主 `window.__previewApi`。
- `src/markdown.js`：markdown-it（表格/任务列表/脚注/高亮）+ 沙箱 HTML 内容块。
- `src/html-embed.js`：HTML 内容块提取、资源打包与离线化。
- `preview.html`：预览宿主页源文件，构建时复制到 `rawfile/web/preview.html`。
- `build-web.js`：esbuild 打包为 `rawfile/web/editor.bundle.js`、`preview.bundle.js`，并生成 `editor.html`、复制 `preview.html`。

构建：

```bash
npm --prefix web-tools ci
node web-tools/build-web.js
```

约束（SDD 6.3、7.3）：

- 所有 JS/CSS/字体本地打包，离线可用；禁止远程资源。
- Markdown 渲染 `html: false`（原始 HTML 标签不执行），并依赖 markdown-it 默认链接协议校验拒绝 `javascript:` 等危险协议。
- HTML 内容块以 `data:text/html;base64` + `sandbox=""` iframe 隔离渲染；独立 HTML 只读预览通过 CSP（`default-src 'none'; script-src 'none'; frame-src 'none'` 等）包裹后 `loadData`，脚本与联网禁用。
- 未引入 DOMPurify（依赖未入仓）；如后续引入，须固定版本并同步 NOTICE。
- 依赖锁定在 `web-tools/package-lock.json`；修改 Web 源码后必须重新打包并提交产物，CI 会校验 bundle 一致性。
