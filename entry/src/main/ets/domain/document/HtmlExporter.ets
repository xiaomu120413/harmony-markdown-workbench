/**
 * 独立 HTML 导出组装（V0.4.3）。
 * 将渲染后的 HTML 片段包装为自包含文件（内联样式，无外部依赖），
 * 样式与 rawfile/web/preview.html 保持一致（浅色为导出基准）。
 * 纯逻辑，可本地单测。
 */
export class HtmlExporter {
  private static escapeHtml(s: string): string {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  /** 文件名：文档名去 .md 后缀（外部 URI 名去参数）+ .html */
  static exportFileName(docTitle: string): string {
    let base = docTitle.trim();
    if (base.toLowerCase().endsWith('.md')) {
      base = base.substring(0, base.length - 3);
    }
    if (base.length === 0) {
      base = '未命名文档';
    }
    return `${base}.html`;
  }

  static buildStandalone(title: string, bodyHtml: string): string {
    const safeTitle = HtmlExporter.escapeHtml(title);
    return [
      '<!DOCTYPE html>',
      '<html lang="zh-CN">',
      '<head>',
      '<meta charset="utf-8">',
      `<title>${safeTitle}</title>`,
      '<style>',
      ':root { --pre-bg: #f4f4f4; --border: #ccc; --inline-code-bg: #f0f0f0; }',
      "body { font-family: -apple-system, 'HarmonyOS Sans', 'Microsoft YaHei', sans-serif; font-size: 15px; line-height: 1.7; color: #182431; background: #ffffff; margin: 0 auto; padding: 24px; max-width: 860px; }",
      '#out h1, #out h2 { border-bottom: 1px solid var(--border); padding-bottom: 6px; }',
      '#out h1 { font-size: 1.7em; } #out h2 { font-size: 1.4em; } #out h3 { font-size: 1.2em; }',
      '#out h4 { font-size: 1.1em; } #out h5 { font-size: 1em; } #out h6 { font-size: 1em; color: var(--border); }',
      '#out pre { background: var(--pre-bg); padding: 10px; border-radius: 8px; overflow: auto; }',
      '#out code { background: var(--inline-code-bg); border-radius: 4px; padding: 1px 5px; }',
      '#out pre code { background: none; padding: 0; }',
      '#out table { border-collapse: collapse; }',
      '#out td, #out th { border: 1px solid var(--border); padding: 4px 10px; }',
      '#out blockquote { margin: 0; padding: 4px 14px; border-left: 3px solid var(--border); color: #8a8f99; }',
      '#out img { max-width: 100%; }',
      '#out .task-list-item { list-style: none; }',
      '#out a { color: #007dff; }',
      '#out hr { border: none; border-top: 1px solid var(--border); }',
      '#out mark { background: #fff3b0; padding: 0 2px; border-radius: 3px; }',
      '#out .footnotes { font-size: 0.9em; color: #8a8f99; border-top: 1px solid var(--border); margin-top: 1.5em; padding-top: 0.5em; }',
      '</style>',
      '</head>',
      '<body>',
      '<div id="out">',
      bodyHtml,
      '</div>',
      '</body>',
      '</html>',
    ].join('\n');
  }
}
