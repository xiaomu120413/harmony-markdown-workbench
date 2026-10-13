/**
 * Markdown 快捷栏命令的文本变换（FR-EDIT-002）。
 * 输入原文与选区，输出变换后文本与新的光标/选区。
 * 规则验收点：
 *  - 包裹型语法（加粗/斜体/删除线/行内代码）作用于当前选区；
 *  - 空选区时插入可继续输入的模板（光标置于内容位置）；
 *  - 块级命令（列表/引用/代码块/标题）按行处理（多行也支持）；
 *  - 两面包裹重复时按"切换"语义撤销包裹（加粗再次执行=去除）；
 *  - 标题命令：同级再执行=取消标题，异级=切换级别（H1⇄H3 等）。
 * 纯逻辑，可本地单测。
 */
export interface TextRange {
  from: number;
  to: number;
}

export interface TextTransformResult {
  text: string;
  selection: TextRange;
}

export type MarkdownCommandName = 'bold' | 'italic' | 'strike' | 'inlineCode' | 'link' | 'image' |
  'ul' | 'ol' | 'task' | 'quote' | 'codeBlock' |
  'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6' | 'hr' | 'table' |
  'indent' | 'outdent' | 'highlight';

export class MarkdownCommands {
  /**
   * 包裹型命令：两侧定界符。若选区已在定界符内则切换为去除（类似编辑器 toggle 语义）。
   */
  private static wrap(text: string, sel: TextRange, left: string, right: string, placeholder: string): TextTransformResult {
    const before = text.substring(0, sel.from);
    const selected = text.substring(sel.from, sel.to);
    const after = text.substring(sel.to);
    const mid = (sel.from + sel.to) / 2;

    // 切换：选区内内容被 left+right 包裹且左右紧邻定界符 → 去除包裹
    if (selected.startsWith(left) && selected.endsWith(right) && selected.length >= left.length + right.length + 1) {
      const inner = selected.substring(left.length, selected.length - right.length);
      return {
        text: before + inner + after,
        selection: { from: sel.from, to: sel.from + inner.length },
      };
    }
    // 空选区：插入 left + placeholder + right，光标停在 placeholder 之后
    if (sel.from === sel.to) {
      return {
        text: before + left + placeholder + right + after,
        selection: { from: sel.from + left.length + placeholder.length, to: sel.from + left.length + placeholder.length },
      };
    }
    // 非空：包裹，选区保持内容（不含定界符）
    return {
      text: before + left + selected + right + after,
      selection: { from: sel.from + left.length, to: sel.from + left.length + selected.length },
    };
  }

  /** 行前缀命令：对选区覆盖的每一行加/去前缀 */
  private static linePrefix(text: string, sel: TextRange, prefix: string, ordered: boolean = false): TextTransformResult {
    const lineStart = text.lastIndexOf('\n', sel.from - 1) + 1;
    let lineEnd = text.indexOf('\n', sel.to);
    if (lineEnd === -1) {
      lineEnd = text.length;
    }
    const block = text.substring(lineStart, lineEnd);
    const lines: string[] = block.split('\n');
    let numbered = 1;
    const newLines: string[] = [];
    for (const line of lines) {
      if (ordered) {
        newLines.push(`${numbered}. ${line}`);
        numbered++;
      } else {
        newLines.push(prefix + line);
      }
    }
    const newBlock = newLines.join('\n');
    const delta = newBlock.length - block.length;
    return {
      text: text.substring(0, lineStart) + newBlock + text.substring(lineEnd),
      selection: { from: sel.from, to: sel.to + delta },
    };
  }

  /**
   * 标题命令（选区覆盖的首行）：同级再执行=取消标题；异级=切换级别；无标题=添加。
   * 光标/选区随行首前缀长度差平移（不低于行首）。
   */
  private static heading(text: string, sel: TextRange, level: number): TextTransformResult {
    const lineStart = text.lastIndexOf('\n', sel.from - 1) + 1;
    let lineEnd = text.indexOf('\n', sel.from);
    if (lineEnd === -1) {
      lineEnd = text.length;
    }
    const line = text.substring(lineStart, lineEnd);
    const m = /^( {0,3})(#{1,6}) /.exec(line);
    const prefix = `${'#'.repeat(level)} `;
    let newLine: string;
    if (m === null) {
      newLine = prefix + line;
    } else if (m[2].length === level) {
      newLine = line.substring(m[0].length);
    } else {
      newLine = prefix + line.substring(m[0].length);
    }
    const delta = newLine.length - line.length;
    const from = Math.max(lineStart, sel.from + delta);
    return {
      text: text.substring(0, lineStart) + newLine + text.substring(lineEnd),
      selection: { from: from, to: Math.max(from, sel.to + delta) },
    };
  }

  /** 片段插入（光标处）：光标落在片段末尾 */
  private static insertSnippet(text: string, sel: TextRange, snippet: string): TextTransformResult {
    const at = sel.from;
    return {
      text: text.substring(0, at) + snippet + text.substring(sel.to),
      selection: { from: at + snippet.length, to: at + snippet.length },
    };
  }

  /**
   * 缩进/减少缩进（嵌套列表层级）：选区覆盖的每行行首 ±2 空格。
   * 减少缩进每行最多移除 2 个前导空格（不足则该行不动）。
   */
  private static shiftIndent(text: string, sel: TextRange, add: boolean): TextTransformResult {
    const lineStart = text.lastIndexOf('\n', sel.from - 1) + 1;
    let lineEnd = text.indexOf('\n', sel.to);
    if (lineEnd === -1) {
      lineEnd = text.length;
    }
    const block = text.substring(lineStart, lineEnd);
    const lines: string[] = block.split('\n');
    const newLines: string[] = [];
    for (const line of lines) {
      if (add) {
        newLines.push('  ' + line);
      } else {
        const m = /^ {1,2}/.exec(line);
        newLines.push(m === null ? line : line.substring(m[0].length));
      }
    }
    const newBlock = newLines.join('\n');
    const delta = newBlock.length - block.length;
    return {
      text: text.substring(0, lineStart) + newBlock + text.substring(lineEnd),
      selection: { from: sel.from, to: Math.max(sel.from, sel.to + delta) },
    };
  }

  static apply(text: string, sel: TextRange, command: MarkdownCommandName): TextTransformResult {
    switch (command) {
      case 'bold':
        return MarkdownCommands.wrap(text, sel, '**', '**', '加粗文本');
      case 'italic':
        return MarkdownCommands.wrap(text, sel, '*', '*', '斜体文本');
      case 'strike':
        return MarkdownCommands.wrap(text, sel, '~~', '~~', '删除线文本');
      case 'inlineCode':
        return MarkdownCommands.wrap(text, sel, '`', '`', '代码');
      case 'highlight':
        return MarkdownCommands.wrap(text, sel, '==', '==', '高亮文本');
      case 'link':
        return MarkdownCommands.wrap(text, sel, '[', '](https://)', '链接文字');
      case 'image':
        return MarkdownCommands.wrap(text, sel, '![', '](https://image.png)', '图片描述');
      case 'ul':
        return MarkdownCommands.linePrefix(text, sel, '- ');
      case 'ol':
        return MarkdownCommands.linePrefix(text, sel, '', true);
      case 'task':
        return MarkdownCommands.linePrefix(text, sel, '- [ ] ');
      case 'quote':
        return MarkdownCommands.linePrefix(text, sel, '> ');
      case 'codeBlock':
        return MarkdownCommands.wrap(text, sel, '```\n', '\n```', '');
      case 'h1':
        return MarkdownCommands.heading(text, sel, 1);
      case 'h2':
        return MarkdownCommands.heading(text, sel, 2);
      case 'h3':
        return MarkdownCommands.heading(text, sel, 3);
      case 'h4':
        return MarkdownCommands.heading(text, sel, 4);
      case 'h5':
        return MarkdownCommands.heading(text, sel, 5);
      case 'h6':
        return MarkdownCommands.heading(text, sel, 6);
      case 'hr':
        return MarkdownCommands.insertSnippet(text, sel, '---\n');
      case 'table':
        return MarkdownCommands.insertSnippet(text, sel, '| 列1 | 列2 |\n| --- | --- |\n| 内容 | 内容 |\n');
      case 'indent':
        return MarkdownCommands.shiftIndent(text, sel, true);
      case 'outdent':
        return MarkdownCommands.shiftIndent(text, sel, false);
      default:
        return { text: text, selection: { from: sel.from, to: sel.to } };
    }
  }
}