/**
 * Markdown 大纲提取（FR-PREVIEW-003，M3-03 领域层先行）。
 * - 识别 ATX 标题（# ～ ######）并标记层级；
 * - 相同标题生成稳定且唯一的内部 ID（文本 + 出现序）；
 * - 可增量/防抖使用：单次解析复杂度 O(n)。
 * 纯逻辑，可本地单测。
 */
export interface OutlineItem {
  level: number;
  text: string;
  id: string;
  line: number;
}

export class HeadingOutline {
  static extract(markdown: string): OutlineItem[] {
    const items: OutlineItem[] = [];
    const seen = new Map<string, number>();
    const lines: string[] = markdown.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const m = /^ {0,3}(#{1,6})(?:[ \t]+(.*?))?[ \t]*$/.exec(line);
      if (m !== null && m[1].length <= 6) {
        const level = m[1].length;
        const text = (m[2] === undefined ? '' : m[2]).trim();
        const count = seen.get(text) ?? 0;
        seen.set(text, count + 1);
        const id = count === 0 ? text : `${text}-${count}`;
        items.push({ level: level, text: text, id: id, line: i });
      }
    }
    return items;
  }

  /**
   * 每行起始字符偏移（0 基，长度 = 行数）：大纲条目 line → 编辑器文档偏移的映射。
   * 与 extract 的 line 字段（0 基行号）配套使用；单次 O(n)。
   */
  static lineOffsets(markdown: string): number[] {
    const offsets: number[] = [0];
    for (let i = 0; i < markdown.length; i++) {
      if (markdown.charAt(i) === '\n') {
        offsets.push(i + 1);
      }
    }
    return offsets;
  }
}