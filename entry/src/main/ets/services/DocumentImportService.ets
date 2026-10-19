import { MuLogger } from '../common/MuLogger';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { DroppedDocumentReader } from './DroppedDocumentReader';
import { ExternalUriFileSource } from '../infrastructure/file/ExternalUriFileSource';
import { InternalFileSource } from '../infrastructure/file/InternalFileSource';
import { InternalSource } from '../domain/document/DocumentFileAdapter';
import { RecentFileList } from '../domain/document/RecentFileList';

/** 系统拖放返回缓存副本；必须可靠落入资料库，不能将缓存 URI 记录为原文件。 */
export class DocumentImportService {
  private readonly ctx: common.UIAbilityContext;
  private readonly cancel: (key: string) => void;
  constructor(ctx: common.UIAbilityContext, cancel: (key: string) => void = () => {}) {
    this.ctx = ctx;
    this.cancel = cancel;
  }

  async receive(event: DragEvent): Promise<string> {
    const stage = `${this.ctx.cacheDir}/incoming-${Date.now()}-${Math.floor(Math.random() * 0xffffff)}`;
    fs.mkdirSync(stage);
    try {
      const uri = await DroppedDocumentReader.receive(event, 15000, fileUri.getUriFromPath(stage), this.cancel);
      return await this.importUri(uri);
    } finally {
      // 仅清理由本次操作新建的平面暂存目录，不递归碰用户目录。
      try {
        for (const name of fs.listFileSync(stage)) {
          const path = `${stage}/${name}`;
          if (fs.statSync(path).isFile()) { fs.unlinkSync(path); }
        }
        fs.rmdirSync(stage);
      } catch (e) { MuLogger.warn('temporary import cleanup incomplete'); }
    }
  }

  async importUri(uri: string): Promise<string> {
    const external = new ExternalUriFileSource();
    // Drag/drop imports a private copy; do not retain access to its external source.
    const read = await external.read({ kind: 'external', uri: uri, displayName: '' }, false);
    if (!read.validUtf8) { throw new Error('仅支持 UTF-8 文本文档，原文件未改动'); }
    const internal = new InternalFileSource(this.ctx);
    const originalName = RecentFileList.displayName(uri).replace(/[\\/:*?"<>|\x00-\x1f]/g, '_');
    const extensionAt = originalName.lastIndexOf('.');
    const requested = originalName.substring(0, extensionAt).substring(0, 110) + originalName.substring(extensionAt);
    const existing = internal.listLibrary();
    let name = requested;
    let count = 2;
    while (existing.includes(name)) {
      const current: InternalSource = { kind: 'internal', relativePath: `library/${name}` };
      const saved = await internal.read(current);
      if (saved.validUtf8 && saved.content === read.content) { return current.relativePath; }
      const dot = requested.lastIndexOf('.');
      name = `${requested.substring(0, dot)}(${count})${requested.substring(dot)}`;
      count++;
    }
    const target: InternalSource = { kind: 'internal', relativePath: `library/${name}` };
    const result = await internal.write(target, read.content, { size: 0, contentHash: '' },
      { encoding: read.encoding, lineEnding: read.lineEnding });
    if (!result.ok) { throw new Error('导入副本保存失败，请检查可用空间后重试'); }
    return target.relativePath;
  }
}
