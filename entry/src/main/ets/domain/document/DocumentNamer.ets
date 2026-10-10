/**
 * 新文档命名（V0.2.2 产品化）。
 * 规则：取正文首个非空行（剥离标题井号与 Markdown 记号、清理非法文件名字符）
 * 作为文档名；无可用文本回退「未命名文档」；与资料库现有文件重名时追加 (2)… 序号。
 * 纯逻辑，可本地单测。
 */
export class DocumentNamer {
  static readonly MAX_BASE: number = 30;

  static derive(content: string, existingNames: string[]): string {
    let firstLine = '';
    const lines = content.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length > 0) {
        firstLine = line;
        break;
      }
    }
    let base = firstLine
      .replace(/^#{1,6}\s*/, '')
      .replace(/[*_`~>[\]()#!]/g, '')
      .replace(/[\\/:*?"<>|]/g, '')
      .replace(/\s+/g, ' ')
      .trim();
    if (base.length === 0) {
      base = '未命名文档';
    }
    if (base.length > DocumentNamer.MAX_BASE) {
      base = base.substring(0, DocumentNamer.MAX_BASE).trim();
    }
    let name = `${base}.md`;
    let n = 2;
    while (existingNames.indexOf(name) !== -1) {
      name = `${base}(${n}).md`;
      n++;
    }
    return name;
  }

  /** 自动名判定（新建时标题未输入完成的兜底名） */
  static isAutoName(name: string): boolean {
    return /^未命名文档(\(\d+\))?\.md$/.test(name);
  }

  /**
   * 自动名升级：当前文件为自动名（首次自动保存常发生在标题输入完成前），
   * 且正文此刻能取出实际标题时，返回升级后的新名；否则返回 undefined（维持现状）。
   */
  static upgrade(currentName: string, content: string, existingNames: string[]): string | undefined {
    if (!DocumentNamer.isAutoName(currentName)) {
      return undefined;
    }
    const candidate = DocumentNamer.derive(content, existingNames);
    if (DocumentNamer.isAutoName(candidate)) {
      return undefined;
    }
    return candidate;
  }
}
