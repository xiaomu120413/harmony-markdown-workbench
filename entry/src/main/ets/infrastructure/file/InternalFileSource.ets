import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import {
  DocumentFileAdapter,
  WriteOkResult,
  DocumentSource,
  FileRevisionContract,
  ReadDocumentResult,
  WriteDocumentResult,
  WriteFailResult,
} from '../../domain/document/DocumentFileAdapter';
import { HashUtil } from '../../domain/document/HashUtil';
import { TextEncodingDetector } from '../../domain/document/TextEncoding';
import { TextRoundtrip, DocumentWriteFormat } from '../../domain/document/DocumentFileAdapter';
import { util } from '@kit.ArkTS';
import { SafeFileIO } from './SafeFileIO';
import { FileNameValidator } from '../../domain/document/FileNameValidator';
import { MuLogger } from '../../common/MuLogger';

/**
 * 内部资料库文件适配器（FR-FILE-001 / M1-01）。
 * 路径模型：应用私有目录（filesDir）+ 相对路径（已由 FileNameValidator 校验）。
 * 写策略：临时文件 + fsync + rename 原子替换（SDD FR-SAVE-003）。
 */
export class InternalFileSource implements DocumentFileAdapter {
  private readonly baseDir: string;

  constructor(ctx: common.UIAbilityContext) {
    this.baseDir = ctx.filesDir;
  }

  pathOf(source: DocumentSource): string {
    if (source.kind !== 'internal') {
      throw new Error('internal source required');
    }
    return `${this.baseDir}/${source.relativePath}`;
  }

  async read(source: DocumentSource): Promise<ReadDocumentResult> {
    const path = this.pathOf(source);
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    const stat = fs.statSync(file.fd);
    let bytes: Uint8Array;
    try { bytes = SafeFileIO.readFd(file.fd); }
    finally { fs.closeSync(file.fd); }
    const len = bytes.byteLength;
    const detection = TextEncodingDetector.detect(bytes);
    const decoder = util.TextDecoder.create('utf-8');
    const rawText = len > 0 ? decoder.decodeToString(bytes.subarray(detection.bomOffset)) : '';
    const text = TextRoundtrip.normalizeToLf(rawText);
    return {
      content: text,
      encoding: detection.encoding,
      lineEnding: detection.lineEnding,
      validUtf8: detection.validUtf8,
      revision: {
        size: stat.size,
        contentHash: HashUtil.of(text),
        modifiedTime: stat.mtime,
      },
    };
  }

  async write(source: DocumentSource, content: string, expectedRevision: FileRevisionContract, format?: DocumentWriteFormat): Promise<WriteDocumentResult> {
    const path = this.pathOf(source);
    // 确保父目录存在（容错：已存在时忽略）
    const dir = path.substring(0, path.lastIndexOf('/'));
    try {
      fs.mkdirSync(dir);
    } catch (e) {
      const err: string = String(e);
      if (!err.includes('exist')) {
        // 其他错误交由后续写入暴露
      }
    }
    // 无法读取既有文件时不猜测为“文件不存在”。
    try {
      if (SafeFileIO.exists(path)) {
        const current = await this.read(source);
        if (!current.validUtf8 || current.revision.contentHash !== expectedRevision.contentHash) {
          return { ok: false, reason: 'conflict', message: 'revision mismatch' };
        }
      } else if (expectedRevision.contentHash.length > 0) {
        return { ok: false, reason: 'not_found', message: 'original document is missing' };
      }
      const fmt: DocumentWriteFormat = format ?? { encoding: 'utf-8', lineEnding: 'lf' };
      const out = TextRoundtrip.applyFormat(content, fmt);
      SafeFileIO.atomicText(path, out);
      const encoder = util.TextEncoder.create('utf-8');
      const byteLen = encoder.encodeInto(out).byteLength;
      const ok: WriteOkResult = {
        ok: true,
        revision: { size: byteLen, contentHash: HashUtil.of(content) },
      };
      return ok;
    } catch (e) {
      const fail: WriteFailResult = { ok: false, reason: 'io', message: String(e) };
      return fail;
    }
  }

  async stat(source: DocumentSource): Promise<FileRevisionContract> {
    return (await this.read(source)).revision;
  }

  async canPersistAccess(source: DocumentSource): Promise<boolean> {
    void source;
    return true;
  }

  /** 枚举资料库文档（M5-01：排除回收站与隐藏项）。路径：filesDir/library/ */
  listLibrary(): string[] {
    const names: string[] = [];
    const libDir = `${this.baseDir}/library`;
    try {
      const all = fs.listFileSync(libDir);
      for (let i = 0; i < all.length; i++) {
        const n = all[i];
        if (!n.startsWith('.') && n !== '.trash' && fs.statSync(`${libDir}/${n}`).isFile()) {
          names.push(n);
        }
      }
    } catch (e) {
      // 目录不存在 → 空列表
    }
    return names;
  }

  /** 删除资料库文件（自动名升级后清理旧文件；仅内部源，失败静默——旧文件残留不阻塞重命名） */
  remove(source: DocumentSource): void {
    if (source.kind !== 'internal') {
      return;
    }
    try {
      fs.unlinkSync(this.pathOf(source));
    } catch (e) {
      // 已不存在/IO 失败：忽略
    }
  }

  /**
   * 资料库内重命名（V0.4.2 库管理）：目标名已存在返回 false（不覆盖）；
   * 文件名合法性由调用方（FileNameValidator）先行校验。
   */
  renameLibrary(oldName: string, newName: string): boolean {
    const libDir = `${this.baseDir}/library`;
    try {
      fs.renameSync(`${libDir}/${oldName}`, `${libDir}/${newName}`);
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 用户确认后直接删除应用内文件，不建立回收副本。 */
  deleteLibrary(name: string): boolean {
    if (FileNameValidator.validate(name) !== undefined) {
      MuLogger.warn('[删除] 拒绝无效的应用内文件名');
      return false;
    }
    try {
      fs.unlinkSync(`${this.baseDir}/library/${name}`);
      return true;
    } catch (e) {
      MuLogger.warn('[删除] 应用内文件删除失败');
      return false;
    }
  }

  /**
   * C2：附件管理——复制外部图片到应用私有附件目录（attachments/）。
   * 同名自动避让；返回附件相对路径（attachments/xxx.png），失败返回空串。
   */
  copyToAttachments(sourceUri: string, fileName: string): string {
    const attDir = `${this.baseDir}/attachments`;
    try {
      try {
        fs.mkdirSync(attDir);
      } catch (e) {
        // 已存在
      }
      let target = fileName;
      const existing = this.listAttachments();
      let n = 2;
      while (existing.indexOf(target) !== -1) {
        const dot = fileName.lastIndexOf('.');
        target = dot > 0 ? `${fileName.substring(0, dot)}(${n})${fileName.substring(dot)}` : `${fileName}(${n})`;
        n++;
      }
      target = target.replace(/[\\/<>:"|?*\x00-\x1f]/g, '_').trim();
      if (target === '' || target === '.' || target === '..') { return ''; }
      if (SafeFileIO.exists(`${attDir}/${target}`)) { target = `${Date.now()}-${target}`; }
      const bytes = SafeFileIO.readBytes(sourceUri, 20 * 1024 * 1024);
      SafeFileIO.atomicBytes(`${attDir}/${target}`, bytes);
      return `attachments/${target}`;
    } catch (e) {
      return '';
    }
  }

  /** 枚举附件目录 */
  listAttachments(): string[] {
    const names: string[] = [];
    try {
      const all = fs.listFileSync(`${this.baseDir}/attachments`);
      for (let i = 0; i < all.length; i++) {
        if (!all[i].startsWith('.')) {
          names.push(all[i]);
        }
      }
    } catch (e) {
      // 目录不存在 → 空列表
    }
    return names;
  }

}
