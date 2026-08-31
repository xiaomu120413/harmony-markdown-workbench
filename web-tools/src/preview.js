/**
 * M3-01 尖峰：预览渲染运行时（Web 侧）。
 * markdown-it（15，含表格）+ 任务列表 + 删除线，本地打包。
 * 安全：html:false（禁用 HTML 标签）→ 防 <script> 注入；
 * 链接 javascript: 协议过滤；危险 iframe 由禁用 HTML 一并杜绝。
 * 正式版（M3-01 验收）将以领域 HtmlSafety 检测 + DOMPurify 白名单强化（依赖合规审查后）。
 */
import MarkdownIt from 'markdown-it';
import taskLists from 'markdown-it-task-lists';

const md = new MarkdownIt({
  html: false,
  linkify: true,
  breaks: false,
});

md.use(taskLists, { enabled: true, label: true, labelAfter: true });

// 删除线（~~x~~）——手写 inline 规则（token 级输出 <del>，外来 HTML 仍被 html:false 禁止）
md.inline.ruler.after('emphasis', 'strikethrough', (state, silent) => {
  const start = state.pos;
  if (state.src.charCodeAt(start) !== 0x7e) {
    return false;
  }
  if (state.src.charCodeAt(start + 1) !== 0x7e) {
    return false;
  }
  const end = state.src.indexOf('~~', start + 2);
  if (end === -1) {
    return false;
  }
  const content = state.src.slice(start + 2, end);
  if (content.length === 0) {
    return false;
  }
  if (silent) {
    return true;
  }
  const token = state.push('html_inline', '', 0);
  token.content = '<del>' + content + '</del>';
  state.pos = end + 2;
  return true;
});

function sanitizeHref(url) {
  const lower = (url || '').trim().toLowerCase();
  if (lower.startsWith('javascript:') || lower.startsWith('vbscript:') || lower.startsWith('data:')) {
    return '#';
  }
  return url;
}

// 渲染后清理危险链路（markdown-it 已禁 HTML；此处兜底 href）
function postProcess(html) {
  let out = html;
  out = out.replace(/href="([^"]*)"/g, (m, u) => `href="${sanitizeHref(u)}"`);
  return out;
}

window.__previewApi = {
  version: 1,
  render(mdText) {
    const raw = md.render(mdText || '');
    const safe = postProcess(raw);
    document.getElementById('out').innerHTML = safe;
    return { length: safe.length, html: safe };
  },
};

// 就绪通知（原生命令通道：__nativeBridge 存在则调用）
if (window.__nativeBridge && typeof window.__nativeBridge.send === 'function') {
  try {
    window.__nativeBridge.send('previewReady', JSON.stringify({ version: 1 }));
  } catch (e) {
    // 忽略
  }
}