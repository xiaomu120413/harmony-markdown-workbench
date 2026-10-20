export interface DocumentOpenParams { name?: string; uri?: string; }

/** 单文档入口规则；保留系统授予的 URI 原值用于 IO。 */
export class DocumentIntake {
  static isImage(id: string): boolean {
    try { return /\.(png|jpe?g|gif|webp|bmp)$/i.test(decodeURIComponent(id.split(/[?#]/)[0])); }
    catch (e) { return false; }
  }
  static isHtml(id: string): boolean {
    try { return /\.(html|htm)$/i.test(decodeURIComponent(id.split(/[?#]/)[0])); }
    catch (e) { return false; }
  }
  static page(id: string): string { return DocumentIntake.isHtml(id) ? 'pages/HtmlPreviewPage' : 'pages/EditorPage'; }
  static route(id: string): DocumentOpenParams {
    return id.startsWith('library/') ? { name: id } : { uri: id };
  }
  static select(uris: string[]): string {
    const unique = Array.from(new Set<string>(uris));
    if (unique.length !== 1) { throw new Error('请一次拖入一份文档或图片'); }
    const uri = unique[0];
    let path: string;
    try { path = decodeURIComponent(uri.split(/[?#]/)[0]); }
    catch (e) { throw new Error('文件地址无效，请通过“打开文档”重新选择'); }
    if (!uri.startsWith('file://') || !(/\.(md|markdown|txt|html|htm)$/i.test(path) || DocumentIntake.isImage(uri))) {
      throw new Error('支持 Markdown、txt、HTML 和 PNG/JPEG/GIF/WebP/BMP 图片');
    }
    return uri;
  }
}
