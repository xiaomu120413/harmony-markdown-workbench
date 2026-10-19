export interface DocumentOpenParams { name?: string; uri?: string; }

/** 单文档入口规则；保留系统授予的 URI 原值用于 IO。 */
export class DocumentIntake {
  static route(id: string): DocumentOpenParams {
    return id.startsWith('library/') ? { name: id } : { uri: id };
  }
  static select(uris: string[]): string {
    const unique = Array.from(new Set<string>(uris));
    if (unique.length !== 1) { throw new Error('请一次拖入一份 Markdown 或 txt 文档'); }
    const uri = unique[0];
    let path: string;
    try { path = decodeURIComponent(uri.split(/[?#]/)[0]); }
    catch (e) { throw new Error('文件地址无效，请通过“打开文档”重新选择'); }
    if (!uri.startsWith('file://') || !/\.(md|markdown|txt)$/i.test(path)) {
      throw new Error('支持 Markdown（.md、.markdown）和 .txt；其他文件请用对应应用打开');
    }
    return uri;
  }
}
