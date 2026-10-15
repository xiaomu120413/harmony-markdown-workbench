import { FindReplaceEngine, FindOptions } from '../editor/FindReplaceEngine';

/**
 * 资料库全文搜索（V0.4.3，FR-SEARCH）。
 * 输入库内文档集合（名 + 正文）与查询词，输出每篇命中数与首个命中处的上下文摘录。
 * 匹配语义复用 FindReplaceEngine（大小写/全词开关一致）。
 * 纯逻辑，可本地单测。
 */
export interface LibraryDoc {
  name: string;
  content: string;
}

export interface DocSearchResult {
  name: string;
  count: number;
  /** 首个命中处的上下文（前后各 ~20 字符，供结果列表预览） */
  snippet: string;
}

export class LibrarySearch {
  static readonly SNIPPET_PAD: number = 20;

  static search(docs: LibraryDoc[], query: string, opts: FindOptions): DocSearchResult[] {
    if (query.length === 0) {
      return [];
    }
    const out: DocSearchResult[] = [];
    for (const doc of docs) {
      const matches = FindReplaceEngine.findAll(doc.content, query, opts);
      if (matches.length === 0) {
        continue;
      }
      const first = matches[0];
      const from = Math.max(0, first.from - LibrarySearch.SNIPPET_PAD);
      const to = Math.min(doc.content.length, first.to + LibrarySearch.SNIPPET_PAD);
      out.push({
        name: doc.name,
        count: matches.length,
        snippet: (from > 0 ? '…' : '') + doc.content.substring(from, to).replace(/\n/g, ' ') + (to < doc.content.length ? '…' : ''),
      });
    }
    return out;
  }
}
