import { describe, expect, it } from '@ohos/hypium';
import {
  DocumentFileAdapter,
  DocumentSource,
  FileRevisionContract,
  ReadDocumentResult,
  WriteDocumentResult,
  InternalSource,
  ExternalSource,
  WriteOkResult,
  WriteFailResult,
} from '../main/ets/domain/document/DocumentFileAdapter';

/** 简单内容哈希（契约测试用；生产实现用平台哈希） */
function hashOf(s: string): string {
  let h = 0;
  for (let i = 0; i < s.length; i++) {
    h = (h * 31 + s.charCodeAt(i)) | 0;
  }
  return `h${h}`;
}

/** 内存适配器：实现 DocumentFileAdapter 契约，供契约测试使用（设备适配器挂接同一套测试） */
class InMemoryAdapter implements DocumentFileAdapter {
  files = new Map<string, string>();
  private failNextWrite = false;
  private revSeq = 0;

  keyOf(source: DocumentSource): string {
    return source.kind === 'internal' ? source.relativePath : source.uri;
  }

  setFailNextWrite(fail: boolean): void {
    this.failNextWrite = fail;
  }

  async read(source: DocumentSource): Promise<ReadDocumentResult> {
    const content = this.files.get(this.keyOf(source));
    if (content === undefined) {
      throw new Error('not_found');
    }
    return {
      content: content,
      encoding: 'utf-8',
      lineEnding: content.includes('\r\n') ? 'crlf' : 'lf',
      revision: { size: content.length, contentHash: hashOf(content), modifiedTime: 0 },
    };
  }

  async write(source: DocumentSource, content: string, expectedRevision: FileRevisionContract): Promise<WriteDocumentResult> {
    if (this.failNextWrite) {
      this.failNextWrite = false;
      const fail: WriteDocumentResult = { ok: false, reason: 'io', message: 'simulated io failure' };
      return fail;
    }
    const key = this.keyOf(source);
    const current = this.files.get(key);
    if (current !== undefined && hashOf(current) !== expectedRevision.contentHash) {
      const fail: WriteDocumentResult = { ok: false, reason: 'conflict', message: 'revision mismatch' };
      return fail;
    }
    this.files.set(key, content);
    this.revSeq++;
    const ok: WriteDocumentResult = {
      ok: true, revision: { size: content.length, contentHash: hashOf(content), modifiedTime: this.revSeq }
    };
    return ok;
  }

  async stat(source: DocumentSource): Promise<FileRevisionContract> {
    const content = this.files.get(this.keyOf(source));
    if (content === undefined) {
      throw new Error('not_found');
    }
    return { size: content.length, contentHash: hashOf(content), modifiedTime: 0 };
  }

  async canPersistAccess(source: DocumentSource): Promise<boolean> {
    return source.kind === 'internal';
  }
}

/**
 * M1-01 契约测试（SDD 15.2）：内外部适配器共用。
 * 以 InMemoryAdapter 先行验证契约测试本身；真实适配器（infrastructure/）接入同一套用例。
 */
export default function documentAdapterContractTest(): void {
  describe('DocumentAdapterContract', () => {
    const internal: DocumentSource = { kind: 'internal', relativePath: 'notes/a.md' };
    const external: DocumentSource = { kind: 'external', uri: 'file://docs/x.md', displayName: 'x.md' };

    it('write_then_read_roundtrip', 0, async () => {
      const a = new InMemoryAdapter();
      const w = await a.write(internal, '# hello', { size: 0, contentHash: '' });
      expect(w.ok).assertTrue();
      if ((w as WriteOkResult).ok) {
        const r = await a.read(internal);
        expect(r.content).assertEqual('# hello');
        expect(r.revision.size).assertEqual(7);
      }
    });

    it('read_empty_file', 0, async () => {
      const a = new InMemoryAdapter();
      await a.write(internal, '', { size: 0, contentHash: '' });
      const r = await a.read(internal);
      expect(r.content).assertEqual('');
      expect(r.revision.size).assertEqual(0);
    });

    it('write_conflict_on_revision_mismatch', 0, async () => {
      const a = new InMemoryAdapter();
      await a.write(internal, 'v1', { size: 0, contentHash: '' });
      // 用过期基线写 → conflict
      const w = await a.write(internal, 'v2', { size: 0, contentHash: 'stale' });
      expect(w.ok).assertFalse();
      if (!(w as WriteOkResult).ok) {
        expect((w as WriteFailResult).reason).assertEqual('conflict');
      }
      const r = await a.read(internal);
      expect(r.content).assertEqual('v1');
    });

    it('io_failure_reported', 0, async () => {
      const a = new InMemoryAdapter();
      a.setFailNextWrite(true);
      const w = await a.write(internal, 'x', { size: 0, contentHash: '' });
      expect(w.ok).assertFalse();
      if (!(w as WriteOkResult).ok) {
        expect((w as WriteFailResult).reason).assertEqual('io');
      }
    });

    it('missing_file_stat_throws_not_found', 0, async () => {
      const a = new InMemoryAdapter();
      let thrown = false;
      try {
        await a.stat(internal);
      } catch (e) {
        thrown = true;
      }
      expect(thrown).assertTrue();
    });

    it('external_cannot_persist', 0, async () => {
      const a = new InMemoryAdapter();
      expect(await a.canPersistAccess(external)).assertFalse();
      expect(await a.canPersistAccess(internal)).assertTrue();
    });

    it('crlf_preserved_in_read_result', 0, async () => {
      const a = new InMemoryAdapter();
      await a.write(internal, 'a\r\nb\r\n', { size: 0, contentHash: '' });
      const r = await a.read(internal);
      expect(r.lineEnding).assertEqual('crlf');
    });
  });
}