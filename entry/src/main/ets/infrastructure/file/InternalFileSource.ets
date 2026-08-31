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
import { util } from '@kit.ArkTS';

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
    const raw = new ArrayBuffer(stat.size);
    const len = fs.readSync(file.fd, raw);
    fs.closeSync(file.fd);
    const bytes = new Uint8Array(raw).slice(0, len);
    const detection = TextEncodingDetector.detect(bytes);
    const decoder = util.TextDecoder.create('utf-8');
    const text = len > 0 ? decoder.decodeToString(bytes.subarray(detection.bomOffset)) : '';
    return {
      content: text,
      encoding: detection.encoding,
      lineEnding: detection.lineEnding,
      revision: {
        size: stat.size,
        contentHash: HashUtil.of(text),
        modifiedTime: stat.mtime,
      },
    };
  }

  async write(source: DocumentSource, content: string, expectedRevision: FileRevisionContract): Promise<WriteDocumentResult> {
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
    // 基线校验：已存在文件且哈希不一致 → conflict（不覆盖）
    try {
      const stat = fs.statSync(path);
      const current = new ArrayBuffer(stat.size);
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const len = fs.readSync(file.fd, current);
      fs.closeSync(file.fd);
      const decoder = util.TextDecoder.create('utf-8');
      const text = decoder.decodeToString(new Uint8Array(current).slice(0, len));
      if (HashUtil.of(text) !== expectedRevision.contentHash) {
        const fail: WriteFailResult = { ok: false, reason: 'conflict', message: 'revision mismatch' };
        return fail;
      }
    } catch (e) {
      // 文件不存在：首写，无需基线校验
    }
    try {
      const tmp = `${path}.tmp`;
      const w = fs.openSync(tmp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      if (content.length > 0) {
        fs.writeSync(w.fd, content);
      }
      fs.fsyncSync(w.fd);
      fs.closeSync(w.fd);
      fs.renameSync(tmp, path);
      const ok: WriteOkResult = {
        ok: true,
        revision: { size: content.length, contentHash: HashUtil.of(content) },
      };
      return ok;
    } catch (e) {
      const fail: WriteFailResult = { ok: false, reason: 'io', message: String(e) };
      return fail;
    }
  }

  async stat(source: DocumentSource): Promise<FileRevisionContract> {
    const path = this.pathOf(source);
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    const stat = fs.statSync(file.fd);
    const raw = new ArrayBuffer(stat.size);
    const len = fs.readSync(file.fd, raw);
    fs.closeSync(file.fd);
    const decoder = util.TextDecoder.create('utf-8');
    const text = decoder.decodeToString(new Uint8Array(raw).slice(0, len));
    return { size: stat.size, contentHash: HashUtil.of(text), modifiedTime: stat.mtime };
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
        if (!n.startsWith('.') && n !== '.trash') {
          names.push(n);
        }
      }
    } catch (e) {
      // 目录不存在 → 空列表
    }
    return names;
  }
}