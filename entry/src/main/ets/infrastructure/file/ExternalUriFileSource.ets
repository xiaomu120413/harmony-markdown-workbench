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
 * 外部 URI 文件适配器（FR-FILE-002 / M1-01）。
 * 基于 M0-02 实测结论：
 *  - 授权 URI 单次运行内可读（openSync + fd 读取）；
 *  - 进程重启后授权失效（13900001/13900002）；
 *  - canPersistAccess() = false → 产品按"临时访问 + 重新定位"交付（ADR-009 草案）。
 */
export class ExternalUriFileSource implements DocumentFileAdapter {
  async read(source: DocumentSource): Promise<ReadDocumentResult> {
    const uri = this.uriOf(source);
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
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
      revision: { size: stat.size, contentHash: HashUtil.of(text), modifiedTime: stat.mtime },
    };
  }

  async write(source: DocumentSource, content: string, expectedRevision: FileRevisionContract): Promise<WriteDocumentResult> {
    void expectedRevision;
    const uri = this.uriOf(source);
    try {
      // 外部 URI 无原子替换手段（provider 不保证 rename）；先尝试打开写。
      const file = fs.openSync(uri, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.fsyncSync(file.fd);
      fs.closeSync(file.fd);
      const ok: WriteOkResult = {
        ok: true,
        revision: { size: content.length, contentHash: HashUtil.of(content) },
      };
      return ok;
    } catch (e) {
      const code: string = String(e);
      const reason = code.includes('permission') || code.includes('13900001') || code.includes('13900002')
        ? 'permission'
        : 'io';
      const fail: WriteFailResult = { ok: false, reason: reason, message: code };
      return fail;
    }
  }

  async stat(source: DocumentSource): Promise<FileRevisionContract> {
    const uri = this.uriOf(source);
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const stat = fs.statSync(file.fd);
    fs.closeSync(file.fd);
    return { size: stat.size, contentHash: '', modifiedTime: stat.mtime };
  }

  async canPersistAccess(source: DocumentSource): Promise<boolean> {
    void source;
    return false; // M0-02 实测：单次运行临时授权
  }

  private uriOf(source: DocumentSource): string {
    if (source.kind !== 'external') {
      throw new Error('external source required');
    }
    return source.uri;
  }
}