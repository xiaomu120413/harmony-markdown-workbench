export interface AttachmentReference {
  source: string;
  name: string;
}

export interface AttachmentPlanResult {
  local: AttachmentReference[];
  remote: boolean;
}

/** 使用 Markdown 解析器报告的图片引用，不扫描代码块或猜测 URI 所属目录。 */
export class AttachmentPlan {
  static create(sources: string[]): AttachmentPlanResult {
    const local: AttachmentReference[] = [];
    const seen = new Set<string>();
    let remote = false;
    for (const source of sources) {
      if (/^https?:\/\//i.test(source)) { remote = true; continue; }
      if (/^data:image\/(png|jpeg|gif|webp);base64,/i.test(source)) { continue; }
      const decoded = decodeURIComponent(source);
      const path = decoded.startsWith('./') ? decoded.substring(2) : decoded;
      if (!path.startsWith('attachments/')) {
        throw new Error('图片引用未取得访问权限，请重新插入本地图片后导出');
      }
      const name = path.substring('attachments/'.length);
      if (name.length === 0 || name === '.' || name === '..' || /[\\/\x00-\x1f?#]/.test(name)) {
        throw new Error('图片附件路径无效');
      }
      if (!/\.(png|jpe?g|gif|webp)$/i.test(name)) {
        throw new Error('交付仅支持 PNG、JPEG、GIF、WebP 图片，请转换图片后重试');
      }
      if (!seen.has(source)) { local.push({ source: source, name: name }); seen.add(source); }
    }
    return { local: local, remote: remote };
  }

  static mime(name: string): string {
    const ext = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
    if (ext === 'jpg' || ext === 'jpeg') { return 'image/jpeg'; }
    if (ext === 'gif') { return 'image/gif'; }
    if (ext === 'webp') { return 'image/webp'; }
    return 'image/png';
  }
}
