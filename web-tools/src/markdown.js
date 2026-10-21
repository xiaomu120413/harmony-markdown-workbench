import MarkdownIt from 'markdown-it';
import hljs from 'highlight.js/lib/common';
import taskLists from 'markdown-it-task-lists';
import footnote from 'markdown-it-footnote';
import mark from 'markdown-it-mark';

const md = new MarkdownIt({
  html: false, linkify: true,
  highlight(str, lang) {
    if (lang && hljs.getLanguage(lang) && str.length <= 256 * 1024) {
      try { return hljs.highlight(str, { language: lang }).value; } catch (_) { /* escaped fallback */ }
    }
    return '';
  },
}).use(taskLists).use(footnote).use(mark);

const defaultImage = md.renderer.rules.image;
md.renderer.rules.image = (tokens, index, options, env, renderer) => {
  const source = tokens[index].attrGet('src');
  if (/^attachments\/[^/]+\.txt$/i.test(source) && env.resources?.[source]?.startsWith('data:text/plain;base64,')) {
    try {
      const data = env.resources[source].substring(env.resources[source].indexOf(',') + 1);
      const text = new TextDecoder('utf-8', { fatal: true }).decode(Uint8Array.from(atob(data), c => c.charCodeAt(0)));
      return `<span class="txt-embed" style="display:block"><span style="font-size:12px">TXT 内容${text ? '' : '（空文本）'}</span>` +
        `<pre style="white-space:pre-wrap;overflow:auto;max-height:420px;min-height:2em"><code>${md.utils.escapeHtml(text)}</code></pre></span>`;
    } catch (_) {
      return '<span role="alert">TXT 内容读取失败，请重新插入 UTF-8 文件</span>';
    }
  }
  if (/^attachments\/[^/]+\.html?$/i.test(source) && env.resources?.[source]?.startsWith('data:text/html;base64,')) {
    return `<span class="html-embed" style="display:block"><span style="font-size:12px">HTML 内容</span>` +
      `<iframe sandbox="" referrerpolicy="no-referrer" title="HTML 内容" src="${md.utils.escapeHtml(env.resources[source])}" ` +
      'style="display:block;width:100%;height:420px;border:1px solid #ccc;border-radius:4px"></iframe></span>';
  }
  if (env.resources && Object.prototype.hasOwnProperty.call(env.resources, source)) {
    tokens[index].attrSet('src', env.resources[source]);
  }
  return defaultImage(tokens, index, options, env, renderer);
};

export function inspectMarkdown(text) {
  const images = new Set();
  const walk = (tokens) => {
    for (const token of tokens) {
      if (token.type === 'image') images.add(token.attrGet('src'));
      if (token.children) walk(token.children);
    }
  };
  walk(md.parse(text, {}));
  return JSON.stringify({ images: [...images] });
}

export function renderMarkdown(text, resources = {}) {
  return md.render(text, { resources });
}
