import { describe, expect, it } from '@ohos/hypium';
import { TextRoundtrip, DocumentWriteFormat } from '../main/ets/domain/document/DocumentFileAdapter';

/**
 * A4：正文规范化与格式还原（两层模型：编辑器 LF / 磁盘原格式）。
 */
export default function textRoundtripTest(): void {
  describe('TextRoundtrip', () => {
    const lf: DocumentWriteFormat = { encoding: 'utf-8', lineEnding: 'lf' };
    const crlf: DocumentWriteFormat = { encoding: 'utf-8', lineEnding: 'crlf' };
    const bom: DocumentWriteFormat = { encoding: 'utf-8-bom', lineEnding: 'lf' };
    const bomCrlf: DocumentWriteFormat = { encoding: 'utf-8-bom', lineEnding: 'crlf' };

    it('normalize_crlf_and_lone_cr_to_lf', 0, () => {
      expect(TextRoundtrip.normalizeToLf('a\r\nb\rc\nd')).assertEqual('a\nb\nc\nd');
    });

    it('normalize_idempotent', 0, () => {
      const once = TextRoundtrip.normalizeToLf('a\r\nb');
      expect(TextRoundtrip.normalizeToLf(once)).assertEqual(once);
    });

    it('apply_lf_passthrough', 0, () => {
      expect(TextRoundtrip.applyFormat('a\nb', lf)).assertEqual('a\nb');
    });

    it('apply_crlf_restores_windows_endings', 0, () => {
      expect(TextRoundtrip.applyFormat('a\nb', crlf)).assertEqual('a\r\nb');
    });

    it('apply_bom_prepends_feff', 0, () => {
      const out = TextRoundtrip.applyFormat('a', bom);
      expect(out.charAt(0)).assertEqual('\uFEFF');
      expect(out.length).assertEqual(2);
    });

    it('apply_bom_crlf_combined', 0, () => {
      const out = TextRoundtrip.applyFormat('a\nb', bomCrlf);
      expect(out).assertEqual('\uFEFFa\r\nb');
    });

    it('roundtrip_crlf_file_stable', 0, () => {
      // A4-01：CRLF 文件读入（规范 LF）→ 编辑 → 落盘还原 CRLF → 再读一致
      const disk = '第一行\r\n第二行\r\n';
      const normalized = TextRoundtrip.normalizeToLf(disk);
      expect(normalized).assertEqual('第一行\n第二行\n');
      const written = TextRoundtrip.applyFormat(normalized, crlf);
      expect(written).assertEqual(disk);
    });
  });
}
