import { fileIo as fs } from '@kit.CoreFileKit';
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

/**
 * 外部 URI 文件适配器（FR-FILE-002 / M1-01；A2 重构：冲突预检与 fd 兜底）。
 * 基于 M0-02 实测结论：
 *  - 授权 URI 单次运行内可读（openSync + fd 读取）；
 *  - 进程重启后授权失效（13900001/13900002）；
 *  - canPersistAccess() = false → 产品按"临时访问 + 重新定位"交付（ADR-009 草案）。
 * A2（R03）：写入前重读磁盘并按统一解码/哈希规则与基线比对，变化 → conflict，
 * 禁止先 TRUNC 再判断；所有 fd 在 finally 中关闭（A2-07）。
 */
export class ExternalUriFileSource implements DocumentFileAdapter {
  async read(source: DocumentSource): Promise<ReadDocumentResult> {
    const uri = this.uriOf(source);
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const bytes = SafeFileIO.readFd(file.fd);
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
        revision: { size: stat.size, contentHash: HashUtil.of(text), modifiedTime: stat.mtime },
      };
    } finally {
      if (file !== undefined) {
        try {
          fs.closeSync(file.fd);
        } catch (e) {
          // 关闭失败不掩盖读取结果
        }
      }
    }
  }

  async write(source: DocumentSource, content: string, expectedRevision: FileRevisionContract, format?: DocumentWriteFormat): Promise<WriteDocumentResult> {
    const uri = this.uriOf(source);
    // ---- A2 冲突预检（R03）：写入前重读磁盘，与打开时的基线按同一规则比对 ----
    try {
      const current = await this.read(source);
      if (!current.validUtf8 || (expectedRevision.contentHash !== '' && current.revision.contentHash !== expectedRevision.contentHash)) {
        return { ok: false, reason: 'conflict', message: 'external file changed on disk' };
      }
    } catch (e) {
      return { ok: false, reason: this.classify(e), message: 'pre-write check failed' };
    }
    // ---- 原位写入（provider 不保证原子替换；草稿检查点已先行落盘兜底） ----
    let w: fs.File | undefined = undefined;
    try {
      const fmt: DocumentWriteFormat = format ?? { encoding: 'utf-8', lineEnding: 'lf' };
      const out = TextRoundtrip.applyFormat(content, fmt);
      w = fs.openSync(uri, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      SafeFileIO.writeAll(w.fd, util.TextEncoder.create('utf-8').encodeInto(out));
      fs.fsyncSync(w.fd);
      fs.closeSync(w.fd);
      w = undefined;
      const encoder = util.TextEncoder.create('utf-8');
      const byteLen = encoder.encodeInto(out).byteLength;
      const ok: WriteOkResult = {
        ok: true,
        revision: { size: byteLen, contentHash: HashUtil.of(content) },
      };
      return ok;
    } catch (e) {
      if (w !== undefined) {
        try {
          fs.closeSync(w.fd);
        } catch (ignore) {
          // 关闭失败不掩盖写入错误
        }
      }
      const fail: WriteFailResult = { ok: false, reason: this.classify(e), message: String(e) };
      return fail;
    }
  }

  async stat(source: DocumentSource): Promise<FileRevisionContract> {
    const uri = this.uriOf(source);
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      return { size: stat.size, contentHash: '', modifiedTime: stat.mtime };
    } finally {
      if (file !== undefined) {
        try {
          fs.closeSync(file.fd);
        } catch (e) {
          // 忽略
        }
      }
    }
  }

  async canPersistAccess(source: DocumentSource): Promise<boolean> {
    void source;
    return false; // M0-02 实测：单次运行临时授权
  }

  /** 权限失效（13900001/13900002/permission）与普通 IO 错误分类 */
  private classify(e: ESObject): 'permission' | 'io' {
    const code: string = String(e);
    return code.includes('permission') || code.includes('13900001') || code.includes('13900002') ? 'permission' : 'io';
  }

  private uriOf(source: DocumentSource): string {
    if (source.kind !== 'external') {
      throw new Error('external source required');
    }
    return source.uri;
  }
}
