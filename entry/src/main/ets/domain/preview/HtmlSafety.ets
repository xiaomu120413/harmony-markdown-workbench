/**
 * Markdown HTML 安全过滤检测（FR-PREVIEW-001，M3-01 领域层先行）。
 * 验收语料（SDD M3-01）：<script>、事件属性、javascript: URL、危险 iframe 不得执行。
 * 本层实现白名单策略的"检测"部分（渲染侧由 DOMPurify 等执行过滤）；
 * 检测为纯逻辑，可本地单测。
 */
export interface HtmlSafetyIssue {
  kind: 'dangerous_tag' | 'event_attribute' | 'javascript_url' | 'dangerous_iframe';
  detail: string;
}

export interface HtmlSafetyResult {
  safe: boolean;
  issues: HtmlSafetyIssue[];
}

const DANGEROUS_TAGS: string[] = ['script', 'style', 'object', 'embed', 'link', 'meta', 'base', 'form'];

export class HtmlSafety {
  static inspect(html: string): HtmlSafetyResult {
    const issues: HtmlSafetyIssue[] = [];
    const lower = html.toLowerCase();

    for (const tag of DANGEROUS_TAGS) {
      const re = new RegExp(`<${tag}(\\s|>|/)`, 'g');
      if (re.test(lower)) {
        issues.push({ kind: 'dangerous_tag', detail: `标签 <${tag}>` });
      }
    }

    // 事件属性 on*（onclick/onerror/onload...）
    const eventRe = /\son[a-z]+\s*=/g;
    let m: RegExpExecArray | null;
    while ((m = eventRe.exec(lower)) !== null) {
      issues.push({ kind: 'event_attribute', detail: `事件属性 ${m[0].trim()}` });
    }

    // javascript: URL（带引号或裸）
    const jsRe = /(href|src|action)\s*=\s*["']?\s*javascript:/g;
    if (jsRe.test(lower)) {
      issues.push({ kind: 'javascript_url', detail: 'javascript: URL' });
    }

    // 危险 iframe（允许空白/安全来源才算安全——此处保守：任何带 src 的 iframe 都标记，
    // 白名单来源由渲染层实现；无 src 的空 iframe 不标记）
    const iframeRe = /<iframe[^>]*>/g;
    let im: RegExpExecArray | null;
    while ((im = iframeRe.exec(lower)) !== null) {
      const tag = im[0];
      if (/\ssrc\s*=/.test(tag)) {
        issues.push({ kind: 'dangerous_iframe', detail: '带 src 的 iframe（需白名单校验）' });
      }
    }

    // 内联 style 中的 expression/url(javascript:)
    if (/expression\s*\(/.test(lower) || /url\s*\(\s*["']?\s*javascript:/.test(lower)) {
      issues.push({ kind: 'javascript_url', detail: 'CSS expression/javascript URL' });
    }

    return { safe: issues.length === 0, issues: issues };
  }
}