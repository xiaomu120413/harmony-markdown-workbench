import { parseDocument, DomUtils } from 'htmlparser2';
import { parse, walk, generate } from 'css-tree';

const ROOT = 'https://mumark.invalid/assets/';
const image = /^data:image\/(png|jpeg|gif|webp|svg\+xml|bmp|x-icon|avif);/i;
const localType = /\.(css|png|jpe?g|gif|webp|svg|bmp|ico|avif)$/i;
const forbidden = new Set(['script', 'iframe', 'frame', 'frameset', 'object', 'embed', 'base', 'meta']);
const decodeText = value => new TextDecoder('utf-8', { fatal: true }).decode(Uint8Array.from(atob(value.substring(value.indexOf(',') + 1)), c => c.charCodeAt(0)));

function pathOf(value, base) {
  if (!value || value.startsWith('#') || image.test(value)) return '';
  const url = new URL(value, new URL(base || '', ROOT));
  if (!url.href.startsWith(ROOT)) return '';
  const path = decodeURIComponent(url.pathname.substring('/assets/'.length));
  if (!path || path.length > 1024 || /[\\:%?#\x00-\x1f\x7f]/.test(path) || path.split('/').some(p => !p || p === '.' || p === '..')) {
    throw new Error('HTML 资源路径越界');
  }
  return localType.test(path) ? path : '';
}

/** HTML 与 CSS 在解析树中处理；同一函数的 inspect 模式只返回需要导入的本地资源。 */
function processHtml(html, resources, inspect) {
  const needed = new Set(), cssStack = new Set();
  let cssInput = 0, cssExpansion = 0;
  const resource = (value, base) => {
    const path = pathOf(value, base);
    if (!path) return image.test(value || '') ? value : '';
    needed.add(path);
    return resources[path] || '';
  };
  const css = (text, base = '', context = 'stylesheet') => {
    cssInput += text.length;
    if (cssInput > 16 * 1024 * 1024) throw new Error('CSS 解析总量超过限制');
    const ast = parse(text, { context, parseCustomProperty: true, onParseError(error) { throw error; } });
    walk(ast, { visit: 'Atrule', enter(node, item, list) {
      if (node.name.toLowerCase() !== 'import') return;
      const parts = node.prelude?.children.toArray() || [];
      const first = parts[0];
      const target = first && (first.type === 'Url' || first.type === 'String') ? first.value : '';
      const path = pathOf(target, base), data = resource(target, base);
      let imported = '';
      if (data && path && !cssStack.has(path)) {
        if (cssStack.size >= 16) throw new Error('CSS 引用超过 16 层');
        cssStack.add(path);
        imported = css(decodeText(data), path);
        cssStack.delete(path);
      }
      if (parts.length > 1 && imported) {
        const tail = parts.slice(1);
        if (tail.some(n => n.type !== 'MediaQueryList')) throw new Error('暂不支持此 CSS @import 条件，请合并样式后插入');
        imported = `@media ${tail.map(n => generate(n)).join(' ')}{${imported}}`;
      }
      cssExpansion += imported.length;
      if (cssExpansion > 12 * 1024 * 1024) throw new Error('CSS 展开超过限制');
      list.replace(item, parse(imported).children);
      return this.skip;
    } });
    walk(ast, { visit: 'Url', enter(node) {
      if (!node.value.startsWith('#')) node.value = resource(node.value, base);
    } });
    return generate(ast).replace(/<\/style/gi, '<\\/style');
  };
  const dom = parseDocument(html, { decodeEntities: true });
  let nodes = 0;
  const transform = parent => {
    parent.children = (parent.children || []).flatMap(node => {
      if (++nodes > 100000) throw new Error('HTML 节点过多');
      if (!node.name) return node;
      const name = node.name.toLowerCase(), attrs = node.attribs || {};
      if (forbidden.has(name)) return [];
      for (const key of Object.keys(attrs)) {
        if (/^on/i.test(key) || ['srcdoc', 'formaction', 'action', 'autofocus', 'ping'].includes(key.toLowerCase())) delete attrs[key];
      }
      if (name === 'form') node.name = 'div';
      if (['input', 'button', 'select', 'textarea'].includes(name)) attrs.disabled = '';
      if (attrs.style) attrs.style = css(attrs.style, '', 'declarationList');
      if (name === 'a' && attrs.href && !attrs.href.startsWith('#')) delete attrs.href;
      if (name === 'img') {
        const original = attrs.src || (attrs.srcset || '').split(',')[0].trim().split(/\s+/)[0];
        attrs.src = resource(original, '');
        delete attrs.srcset;
        delete attrs.loading;
      } else if (name === 'source') return [];
      else if (name === 'link') {
        if (!(attrs.rel || '').toLowerCase().split(/\s+/).includes('stylesheet')) return [];
        const path = pathOf(attrs.href, ''), data = resource(attrs.href, '');
        const content = data ? css(decodeText(data), path) : '';
        const replacement = parseDocument(`<style>${content}</style>`).children[0];
        if (attrs.media) replacement.attribs.media = attrs.media;
        replacement.parent = parent;
        return replacement;
      } else if (name === 'style') {
        const content = css(DomUtils.textContent(node));
        const replacement = parseDocument(`<style>${content}</style>`).children[0];
        replacement.parent = parent;
        return replacement;
      }
      transform(node);
      return node;
    });
  };
  transform(dom);
  if (inspect) return JSON.stringify([...needed]);
  const missing = [...needed].filter(p => !resources[p]);
  if (missing.length) throw new Error(`HTML 仍缺少 ${missing.length} 个本地资源`);
  const policy = "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src data:; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'";
  return '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
    `<meta http-equiv="Content-Security-Policy" content="${policy}">` +
    '<style>img{max-width:100%}body{overflow-wrap:anywhere}</style></head><body>' + DomUtils.getOuterHTML(dom) + '</body></html>';
}

export const inspectHtml = (html, resources = {}) => processHtml(html, resources, true);
export const bundleHtml = (html, resources = {}) => processHtml(html, resources, false);
