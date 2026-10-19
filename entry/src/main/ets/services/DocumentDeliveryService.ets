import { MuLogger } from '../common/MuLogger';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { zlib } from '@kit.BasicServicesKit';
import { AttachmentPlan } from '../domain/document/AttachmentPlan';
import { HtmlExporter } from '../domain/document/HtmlExporter';
import { SafeFileIO } from '../infrastructure/file/SafeFileIO';

export interface DeliveryResult { uri: string; fileName: string; remoteImages: boolean; }

/** 冻结正文准备完整产物后才打开目标选择器；取消和失败不改变编辑会话。 */
export class DocumentDeliveryService {
  private readonly ctx: common.UIAbilityContext;
  constructor(ctx: common.UIAbilityContext) { this.ctx = ctx; }

  private name(title: string, extension: string): string {
    let base = title.replace(/\.(md|markdown|txt)$/i, '').replace(/[\\/:*?"<>|\x00-\x1f]/g, '_').trim();
    if (base.length === 0) { base = '未命名文档'; }
    return `${base.substring(0, 100)}.${extension}`;
  }

  private chosenName(uri: string, fallback: string): string {
    const path = uri.split('?')[0];
    const tail = path.substring(path.lastIndexOf('/') + 1);
    try {
      const name = decodeURIComponent(tail);
      return name.length > 0 && !/[\x00-\x1f\\/]/.test(name) ? name : fallback;
    } catch (e) { return fallback; }
  }

  async markdown(title: string, text: string): Promise<DeliveryResult | undefined> {
    const name = this.name(title, 'md');
    const target = await this.choose(name);
    if (target === undefined) { return undefined; }
    SafeFileIO.replaceTextTarget(target, text);
    return { uri: target, fileName: this.chosenName(target, name), remoteImages: false };
  }

  async html(title: string, text: string, sources: string[],
    render: (text: string, resources: Record<string, string>) => Promise<string>): Promise<DeliveryResult | undefined> {
    const resources = this.resources(sources);
    const body = await render(text, resources);
    const html = HtmlExporter.buildStandalone(title, body);
    const name = this.name(title, 'html');
    const target = await this.choose(name);
    if (target === undefined) { return undefined; }
    SafeFileIO.replaceTextTarget(target, html);
    return { uri: target, fileName: this.chosenName(target, name), remoteImages: AttachmentPlan.create(sources).remote };
  }

  resources(sources: string[]): Record<string, string> {
    const plan = AttachmentPlan.create(sources);
    const resources: Record<string, string> = {};
    let total = 0;
    for (const ref of plan.local) {
      const bytes = SafeFileIO.readBytes(`${this.ctx.filesDir}/attachments/${ref.name}`, 20 * 1024 * 1024);
      total += bytes.byteLength;
      if (total > 20 * 1024 * 1024) { throw new Error('HTML 图片总量超过 20 MiB，请改用图文 ZIP'); }
      resources[ref.source] = `data:${AttachmentPlan.mime(ref.name)};base64,${new util.Base64Helper().encodeToStringSync(bytes)}`;
    }
    return resources;
  }

  async zip(title: string, text: string, sources: string[]): Promise<DeliveryResult | undefined> {
    const plan = AttachmentPlan.create(sources);
    const root = `${this.ctx.cacheDir}/mumark-${Date.now()}-${Math.floor(Math.random() * 0xffffff)}`;
    const folder = `${root}/document`;
    const archive = `${root}/document.zip`;
    const files: string[] = [];
    let attachmentDir = false;
    fs.mkdirSync(root);
    try {
      fs.mkdirSync(folder);
      const document = `${folder}/document.md`;
      SafeFileIO.writeText(document, text);
      files.push(document);
      if (plan.local.length > 0) { fs.mkdirSync(`${folder}/attachments`); attachmentDir = true; }
      let total = 0;
      const copied = new Set<string>();
      for (const ref of plan.local) {
        if (copied.has(ref.name)) { continue; }
        const bytes = SafeFileIO.readBytes(`${this.ctx.filesDir}/attachments/${ref.name}`, 20 * 1024 * 1024);
        total += bytes.byteLength;
        if (total > 100 * 1024 * 1024) { throw new Error('ZIP 图片总量超过 100 MiB'); }
        const path = `${folder}/attachments/${ref.name}`;
        files.push(path);
        SafeFileIO.writeBytes(path, bytes);
        copied.add(ref.name);
      }
      await zlib.compressFile(folder, archive, {});
      const name = this.name(title, 'zip');
      const target = await this.choose(name);
      if (target === undefined) { return undefined; }
      this.publish(archive, target);
      return { uri: target, fileName: this.chosenName(target, name), remoteImages: plan.remote };
    } finally {
      for (const path of files) { this.remove(path); }
      this.remove(archive);
      try {
        if (attachmentDir) { fs.rmdirSync(`${folder}/attachments`); }
        fs.rmdirSync(folder);
        fs.rmdirSync(root);
      } catch (e) { MuLogger.warn('temporary directory cleanup failed'); }
    }
  }

  private async choose(name: string): Promise<string | undefined> {
    const uris = await new picker.DocumentViewPicker(this.ctx).save({ newFileNames: [name] });
    return uris.length === 0 ? undefined : uris[0];
  }

  private publish(source: string, target: string): void {
    const input = fs.openSync(source, fs.OpenMode.READ_ONLY);
    try {
      SafeFileIO.replaceTarget(target, (fd: number) => {
        const size = fs.statSync(input.fd).size;
        let offset = 0;
        while (offset < size) {
          const buffer = new ArrayBuffer(Math.min(size - offset, 256 * 1024));
          const n = fs.readSync(input.fd, buffer);
          if (n <= 0) { throw new Error('导出包读取不完整'); }
          SafeFileIO.writeAll(fd, new Uint8Array(buffer, 0, n));
          offset += n;
        }
      });
    } finally { fs.closeSync(input.fd); }
  }

  private remove(path: string): void {
    try { if (fs.accessSync(path)) { fs.unlinkSync(path); } }
    catch (e) { MuLogger.warn('temporary file cleanup failed'); }
  }
}
