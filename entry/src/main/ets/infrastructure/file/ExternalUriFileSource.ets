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
import { util } from '@kit.ArkTS';

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
      const raw = new ArrayBuffer(stat.size);
      const len = fs.readSync(file.fd, raw);
      const bytes = new Uint8Array(raw).slice(0, len);
      const detection = TextEncodingDetector.detect(bytes);
      const decoder = util.TextDecoder.create('utf-8');
      const text = len > 0 ? decoder.decodeToString(bytes.subarray(detection.bomOffset)) : '';
      return {
        content: text,
        encoding: detection.encoding,
        lineEnding: detection.lineEnding,
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

  async write(source: DocumentSource, content: string, expectedRevision: FileRevisionContract): Promise<WriteDocumentResult> {
    const uri = this.uriOf(source);
    // ---- A2 冲突预检（R03）：写入前重读磁盘，与打开时的基线按同一规则比对 ----
    let check: fs.File | undefined = undefined;
    try {
      check = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(check.fd);
      const raw = new ArrayBuffer(stat.size);
      const len = fs.readSync(check.fd, raw);
      fs.closeSync(check.fd);
      check = undefined;
      const bytes = new Uint8Array(raw).slice(0, len);
      const detection = TextEncodingDetector.detect(bytes);
      const decoder = util.TextDecoder.create('utf-8');
      const text = len > 0 ? decoder.decodeToString(bytes.subarray(detection.bomOffset)) : '';
      const diskHash = HashUtil.of(text);
      if (expectedRevision.contentHash !== '' && diskHash !== expectedRevision.contentHash) {
        const conflict: WriteFailResult = { ok: false, reason: 'conflict', message: 'external file changed on disk' };
        return conflict;
      }
    } catch (e) {
      if (check !== undefined) {
        try {
          fs.closeSync(check.fd);
        } catch (ignore) {
          // 读取检查失败按权限/IO 分类返回，不继续写入
        }
      }
      const reason = this.classify(e);
      if (reason === 'permission') {
        const fail: WriteFailResult = { ok: false, reason: reason, message: String(e) };
        return fail;
      }
      // 检查读取失败（非权限）：不盲写（无法核对基线 → 原位写入不安全）
      const fail: WriteFailResult = { ok: false, reason: 'io', message: `pre-write check failed: ${String(e)}` };
      return fail;
    }
    // ---- 原位写入（provider 不保证原子替换；草稿检查点已先行落盘兜底） ----
    let w: fs.File | undefined = undefined;
    try {
      w = fs.openSync(uri, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      if (content.length > 0) {
        fs.writeSync(w.fd, content);
      }
      fs.fsyncSync(w.fd);
      fs.closeSync(w.fd);
      w = undefined;
      const encoder = util.TextEncoder.create('utf-8');
      const byteLen = encoder.encodeInto(content).byteLength;
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
