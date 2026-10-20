/**
 * M3-01 尖峰：预览渲染运行时（Web 侧）。
 * markdown-it（15，含表格）+ 任务列表 + 删除线，本地打包。
 * 安全：html:false（禁用 HTML 标签）→ 防 <script> 注入；
 * 链接 javascript: 协议过滤；HTML 内容块用 sandbox iframe 隔离。
 */
import { renderMarkdown } from './markdown';

let lastHtml = '';
// 预览页生命周期内缓存已下发的资源；宿主只发增量，大 HTML/图片不重复跨桥。
let resourceCache = {};
let resourceEpoch = -1;

/**
 * 用新渲染结果替换预览 DOM。
 * HTML 内容块的 iframe src 是数 MB 的 data URI，整树重建会让每个 iframe 重新加载并闪白；
 * 图片（尤其大图）重建也会重新解码。src 未变的节点直接搬移旧节点，保留已加载内容；
 * markdown 已禁用原始 HTML，sandbox iframe 仅来自内容块。
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

function groupBySource(nodes) {
  const grouped = new Map();
  for (let i = 0; i < nodes.length; i++) {
    const key = nodes[i].getAttribute('src');
    const list = grouped.get(key);
    if (list) { list.push(nodes[i]); } else { grouped.set(key, [nodes[i]]); }
  }
  return grouped;
}

/** 相同 src 且 alt/title 未变时复用图片节点，避免大图重新解码闪烁。 */
function reuseImages(out, staging) {
  const previous = groupBySource(out.querySelectorAll('img[src]'));
  const next = staging.querySelectorAll('img[src]');
  for (let i = 0; i < next.length; i++) {
    const image = next[i];
    const list = previous.get(image.getAttribute('src'));
    if (!list || list.length === 0) { continue; }
    for (let j = 0; j < list.length; j++) {
      const old = list[j];
      if (old.getAttribute('alt') === image.getAttribute('alt') &&
        old.getAttribute('title') === image.getAttribute('title')) {
        image.replaceWith(old);
        list.splice(j, 1);
        break;
      }
    }
  }
}

function reuseHtmlEmbeds(out, staging) {
  const previous = groupBySource(htmlEmbedFrames(out));
  const next = htmlEmbedFrames(staging);
  for (let i = 0; i < next.length; i++) {
    const list = previous.get(next[i].getAttribute('src'));
    const old = list && list.shift();
    if (old) { next[i].replaceWith(old); }
  }
}

function mountPreview(out, safe) {
  const scroller = document.scrollingElement || document.documentElement;
  const scrollTop = scroller ? scroller.scrollTop : 0;
  const staging = document.createElement('div');
  staging.innerHTML = safe;
  reuseImages(out, staging);
  reuseHtmlEmbeds(out, staging);
  while (out.firstChild) { out.removeChild(out.firstChild); }
  while (staging.firstChild) { out.appendChild(staging.firstChild); }
  if (scroller) { scroller.scrollTop = scrollTop; }
}

window.__previewApi = {
  version: 1,
  render(mdText, resources = {}, epoch = 0) {
    if (epoch !== resourceEpoch) {
      resourceCache = {};
      resourceEpoch = epoch;
    }
    const keys = Object.keys(resources);
    for (let i = 0; i < keys.length; i++) {
      resourceCache[keys[i]] = resources[keys[i]];
    }
    const safe = renderMarkdown(mdText || '', resourceCache);
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
