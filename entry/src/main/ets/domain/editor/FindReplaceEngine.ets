/**
 * 文档内查找替换（FR-EDIT-004，M3-04 领域层先行）。
 * - 大小写敏感开关、全词匹配；
 * - 替换当前 / 全部替换；
 * - 结果提供一次撤销所需信息（替换位置与旧文本列表）。
 * 纯逻辑，可本地单测（作用于字符串，不依赖编辑器）。
 */
export interface FindOptions {
  caseSensitive: boolean;
  wholeWord: boolean;
}

export interface FindMatch {
  from: number;
  to: number;
}

export interface UndoRecord {
  from: number;
  to: number;
  oldText: string;
}

export interface ReplaceAllResult {
  text: string;
  count: number;
  /** 撤销信息：每处替换的 [from,to) 与旧文本 */
  undos: Array<UndoRecord>;
}

export interface ReplaceCurrentResult {
  text: string;
  count: number;
  newCursor: number;
  replaced: boolean;
}

export class FindReplaceEngine {
  static findAll(text: string, query: string, opts: FindOptions): FindMatch[] {
    if (query.length === 0) {
      return [];
    }
    const results: FindMatch[] = [];
    const hay = opts.caseSensitive ? text : text.toLowerCase();
    const needle = opts.caseSensitive ? query : query.toLowerCase();
    let idx = 0;
    while (true) {
      const found = hay.indexOf(needle, idx);
      if (found === -1) {
        break;
      }
      if (!opts.wholeWord || FindReplaceEngine.isWordBoundary(text, found, found + query.length)) {
        results.push({ from: found, to: found + query.length });
      }
      idx = found + query.length;
    }
    return results;
  }

  /** 全词匹配：匹配段前后不是字母/数字/下划线 */
  private static isWordBoundary(text: string, from: number, to: number): boolean {
    const isWordChar = (c: string): boolean => /[A-Za-z0-9_]/.test(c);
    if (from > 0 && isWordChar(text.charAt(from - 1))) {
      return false;
    }
    if (to < text.length && isWordChar(text.charAt(to))) {
      return false;
    }
    return true;
  }

  static replaceAll(text: string, query: string, replacement: string, opts: FindOptions): ReplaceAllResult {
    const matches = FindReplaceEngine.findAll(text, query, opts);
    const undos: Array<UndoRecord> = [];
    let result = '';
    let cursor = 0;
    for (const m of matches) {
      result += text.substring(cursor, m.from) + replacement;
      undos.push({ from: m.from, to: m.from + replacement.length, oldText: text.substring(m.from, m.to) });
      cursor = m.to;
    }
    result += text.substring(cursor);
    const out: ReplaceAllResult = { text: result, count: matches.length, undos: undos };
    return out;
  }

  /** 替换当前匹配（从 position 之后搜索第一个），返回新文本与新的光标 */
  static replaceCurrent(
    text: string, query: string, replacement: string, from: number, opts: FindOptions,
  ): ReplaceCurrentResult {
    const matches = FindReplaceEngine.findAll(text, query, opts);
    for (const m of matches) {
      if (m.from >= from) {
        const next = text.substring(0, m.from) + replacement + text.substring(m.to);
        const okResult: ReplaceCurrentResult = {
          text: next,
          count: matches.length,
          newCursor: m.from + replacement.length,
          replaced: true,
        };
        return okResult;
      }
    }
    // 无后续匹配：回绕从 0 再找
    for (const m of matches) {
      if (m.from < from) {
        const next = text.substring(0, m.from) + replacement + text.substring(m.to);
        const wrapResult: ReplaceCurrentResult = {
          text: next, count: matches.length, newCursor: m.from + replacement.length, replaced: true,
        };
        return wrapResult;
      }
    }
    const noResult: ReplaceCurrentResult = { text: text, count: 0, newCursor: from, replaced: false };
    return noResult;
  }
}