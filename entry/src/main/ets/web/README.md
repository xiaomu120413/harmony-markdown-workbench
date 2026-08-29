# web/ 层

ArkWeb 编辑运行时资源（SDD 7.2 / ADR-001、ADR-005）。M2-01 之前不放置业务代码。

- `index.html`：编辑器宿主页（M2-01）
- `editor.ts`：CodeMirror 6 编辑封装（M2-01）
- `preview.ts`：markdown-it + Sanitizer 安全预览（M3-01）
- `bridge.ts`：与原生 JSBridge 协议实现（M2-02）
- `styles/`：编辑器与预览样式

约束（SDD 6.3、7.3）：

- 所有 JS/CSS/字体本地打包，离线可用；禁止远程资源。
- Markdown HTML 必须经过白名单过滤（DOMPurify），禁止脚本执行。
- 依赖必须固定版本并进入 NOTICE（M2-01 验收）。