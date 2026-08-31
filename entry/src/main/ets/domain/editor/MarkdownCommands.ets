/**
 * Markdown 快捷栏命令的文本变换（FR-EDIT-002）。
 * 输入原文与选区，输出变换后文本与新的光标/选区。
 * 规则验收点：
 *  - 包裹型语法（加粗/斜体/删除线/行内代码）作用于当前选区；
 *  - 空选区时插入可继续输入的模板（光标置于内容位置）；
 *  - 块级命令（列表/引用/代码块）按行处理（多行也支持）；
 *  - 两面包裹重复时按"切换"语义撤销包裹（加粗再次执行=去除）。
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
  'ul' | 'ol' | 'task' | 'quote' | 'codeBlock';

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
      default:
        return { text: text, selection: { from: sel.from, to: sel.to } };
    }
  }
}