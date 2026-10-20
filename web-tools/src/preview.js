/**
 * M3-01 尖峰：预览渲染运行时（Web 侧）。
 * markdown-it（15，含表格）+ 任务列表 + 删除线，本地打包。
 * 安全：html:false（禁用 HTML 标签）→ 防 <script> 注入；
 * 链接 javascript: 协议过滤；HTML 内容块用 sandbox iframe 隔离。
 */
import { renderMarkdown } from './markdown';

let lastHtml = '';

/**
 * 用新渲染结果替换预览 DOM。
 * HTML 内容块的 iframe src 是数 MB 的 data URI，整树重建会让每个 iframe 重新加载并闪白；
 * src 未变的 iframe 直接搬移旧节点，保留已加载内容（markdown 已禁用原始 HTML，sandbox iframe 仅来自内容块）。
 */
function htmlEmbedFrames(root) {
  const frames = root.querySelectorAll('iframe[sandbox]');
  const found = [];
  for (let i = 0; i < frames.length; i++) {
    const src = frames[i].getAttribute('src') || '';
    if (src.startsWith('data:text/html;base64,')) { found.push(frames[i]); }
  }
  return found;
}

function mountPreview(out, safe) {
  const staging = document.createElement('div');
  staging.innerHTML = safe;
  const previous = new Map();
  const oldFrames = htmlEmbedFrames(out);
  for (let i = 0; i < oldFrames.length; i++) {
    const key = oldFrames[i].getAttribute('src');
    const list = previous.get(key);
    if (list) { list.push(oldFrames[i]); } else { previous.set(key, [oldFrames[i]]); }
  }
  const nextFrames = htmlEmbedFrames(staging);
  for (let i = 0; i < nextFrames.length; i++) {
    const key = nextFrames[i].getAttribute('src');
    const list = previous.get(key);
    const old = list && list.shift();
    if (old) { nextFrames[i].replaceWith(old); }
  }
  while (out.firstChild) { out.removeChild(out.firstChild); }
  while (staging.firstChild) { out.appendChild(staging.firstChild); }
}

window.__previewApi = {
  version: 1,
  render(mdText, resources = {}) {
    const safe = renderMarkdown(mdText || '', resources);
    lastHtml = safe;
    mountPreview(document.getElementById('out'), safe);
    return { length: safe.length, html: safe };
  },
  /**
   * D1：滚动到源行号对应的预览块。
   * markdown-it 渲染后行号信息不直接保留——用标题锚点近似定位
   * （找到 ≤ line 的最大标题行号对应的元素，滚动到该元素）。
   */
  scrollToLine(line, sourceText) {
    // 解析源文本，建立 行号 → 标题文本 映射
    const lines = (sourceText || '').split('\n');
    let bestHeading = '';
    let bestLine = 0;
    for (let i = 0; i < lines.length && i < line; i++) {
      const m = /^#{1,6}\s+(.+)/.exec(lines[i]);
      if (m) {
        bestHeading = m[1].trim();
        bestLine = i + 1;
      }
    }
    if (!bestHeading) {
      return; // 无标题锚点：不滚动
    }
    // 在预览 DOM 中查找匹配的标题元素
    const out = document.getElementById('out');
    const headings = out.querySelectorAll('h1,h2,h3,h4,h5,h6');
    for (let i = 0; i < headings.length; i++) {
      if (headings[i].textContent.trim() === bestHeading) {
        headings[i].scrollIntoView({ behavior: 'smooth', block: 'start' });
        return;
      }
    }
  },
  /** 最近一次渲染的 HTML（导出/复制用） */
  getHtml() {
    return lastHtml;
  },
  /** 主题跟随编辑器（M5-03 设置：dark） */
  setDark(dark) {
    document.body.classList.toggle('dark', !!dark);
  },
  /** 字号跟随编辑器（M5-03 设置） */
  setFontSize(px) {
    document.body.style.fontSize = px + 'px';
  },
};

// 就绪通知（原生命令通道：__nativeBridge 存在则发送 JSON 信封）
if (window.__nativeBridge && typeof window.__nativeBridge.send === 'function') {
  try {
    window.__nativeBridge.send(JSON.stringify({ version: 1, id: 'ready-' + Date.now(), type: 'previewReady', payload: { version: 1 } }));
  } catch (e) {
    // 忽略
  }
}
