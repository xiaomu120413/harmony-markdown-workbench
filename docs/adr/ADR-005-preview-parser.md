# ADR-005：预览使用成熟 JS 解析器

- 状态：建议接受，M0-03/M3-01 后确认。
- 背景：GFM 完整度（表格、任务列表、删除线等）与维护成本优于自研 ArkTS 解析器。
- 决策：使用 markdown-it（或 ADR 批准的等价解析器）+ DOMPurify 白名单净化，运行于 ArkWeb；所有 JS/CSS/字体本地打包。
- 后果：需要 HTML 安全过滤（禁止脚本、事件属性、`javascript:` URL、危险 iframe）与离线 CSP；依赖固定版本并进入 NOTICE。
- 关联：FR-PREVIEW-001；M3-01；R-09。