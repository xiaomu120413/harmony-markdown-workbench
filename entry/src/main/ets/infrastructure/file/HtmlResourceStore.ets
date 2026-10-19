import { fileIo as fs } from '@kit.CoreFileKit';
import { SafeFileIO } from './SafeFileIO';
import { MuLogger } from '../../common/MuLogger';

export interface HtmlResource { bytes: Uint8Array; mime: string; }

/** 一次插入的临时资源集合；完成后只保留最终自包含 HTML 附件。 */
export class HtmlResourceStore {
  static readonly BASE: string = 'https://mumark.invalid/assets/';
  private root: string;
  private resources: Map<string, HtmlResource> = new Map();
  private missing: Set<string> = new Set();
  constructor(root: string = '') { this.root = root; }

  static path(url: string): string {
    if (!url.startsWith(HtmlResourceStore.BASE)) { throw new Error('资源来源不受支持'); }
    const path = decodeURIComponent(url.substring(HtmlResourceStore.BASE.length).split(/[?#]/)[0]);
    if (!path || path.length > 1024 || /[\\:%?#\x00-\x1f\x7f]/.test(path) ||
      path.split('/').some((part: string) => part === '' || part === '.' || part === '..')) {
      throw new Error('资源路径超出文档目录');
    }
    return path;
  }
  static mime(path: string): string {
    switch (path.substring(path.lastIndexOf('.') + 1).toLowerCase()) {
      case 'css': return 'text/css';
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'svg': return 'image/svg+xml';
      case 'bmp': return 'image/bmp';
      case 'ico': return 'image/x-icon';
      case 'avif': return 'image/avif';
      default: throw new Error('仅导入 CSS 和图片');
    }
  }
  private static child(root: string, path: string): string {
    const index = root.indexOf('?');
    const base = index < 0 ? root : root.substring(0, index);
    const query = index < 0 ? '' : root.substring(index);
    return base.replace(/\/$/, '') + '/' + path.split('/').map((s: string) => encodeURIComponent(s)).join('/') + query;
  }
  private put(path: string, bytes: Uint8Array, mime: string): void {
    let total = bytes.byteLength;
    for (const key of this.resources.keys()) { if (key !== path) { total += this.resources.get(key)?.bytes.byteLength ?? 0; } }
    if (bytes.byteLength > 4 * 1024 * 1024 || total > 32 * 1024 * 1024 ||
      (!this.resources.has(path) && this.resources.size >= 128)) {
      throw new Error('资源超过插入限额（单个 4 MiB、共 128 个 / 32 MiB）');
    }
    this.resources.set(path, { bytes: bytes, mime: mime });
    this.missing.delete(path);
  }
  read(url: string): HtmlResource {
    const path = HtmlResourceStore.path(url);
    const mime = HtmlResourceStore.mime(path);
    const existing = this.resources.get(path);
    if (existing !== undefined) { return existing; }
    try {
      if (!this.root) { throw new Error('尚未选择资源'); }
      let source = this.root;
      for (const part of path.split('/')) {
        source = HtmlResourceStore.child(source, part);
        if (fs.lstatSync(source).isSymbolicLink()) { throw new Error('不导入符号链接资源'); }
      }
      const bytes = SafeFileIO.readBytes(source, 4 * 1024 * 1024);
      this.put(path, bytes, mime);
      return { bytes: bytes, mime: mime };
    } catch (e) {
      this.missing.add(path);
      const error: ESObject = e as ESObject;
      MuLogger.warn(`HTML local resource unavailable, code=${String(error.code ?? 'unknown')}`);
      throw new Error(String(e));
    }
  }
  useFolder(uri: string): void {
    if (!uri.startsWith('file://') || !fs.statSync(uri).isDirectory()) { throw new Error('请选择 HTML 所在目录，或改用选择资源文件'); }
    this.root = uri;
  }
  importFiles(uris: string[]): void {
    let root = '';
    for (const uri of uris) {
      const decoded = decodeURIComponent(uri.split(/[?#]/)[0]);
      for (const path of this.missing) {
        if (decoded.endsWith('/' + path)) { root = decoded.substring(0, decoded.length - path.length); break; }
      }
      if (root) { break; }
    }
    if (!root) { throw new Error('所选文件未匹配 HTML 引用，请选择保留原目录结构的图片或 CSS'); }
    let count = 0;
    for (const uri of uris) {
      const decoded = decodeURIComponent(uri.split(/[?#]/)[0]);
      if (!decoded.startsWith(root)) { continue; }
      const path = HtmlResourceStore.path(HtmlResourceStore.BASE + encodeURI(decoded.substring(root.length)));
      const mime = HtmlResourceStore.mime(path);
      this.put(path, SafeFileIO.readBytes(uri, 4 * 1024 * 1024), mime);
      count++;
    }
    if (!count) { throw new Error('未导入可用资源'); }
  }
}
