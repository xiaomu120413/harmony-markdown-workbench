import { describe, expect, it } from '@ohos/hypium';
import { TextEncodingDetector, TextEncodingResult } from '../main/ets/domain/document/TextEncoding';

function utf8Of(s: string): Uint8Array {
  // 测试环境（Node）用 TextEncoder；此处用逐字符构造避免依赖
  const out: number[] = [];
  for (const ch of s) {
    const cp = ch.codePointAt(0) as number;
    if (cp < 0x80) {
      out.push(cp);
    } else if (cp < 0x800) {
      out.push(0xc0 | (cp >> 6), 0x80 | (cp & 0x3f));
    } else if (cp < 0x10000) {
      out.push(0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
    } else {
      out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
    }
  }
  return new Uint8Array(out);
}

function withBom(inner: Uint8Array): Uint8Array {
  const out = new Uint8Array(inner.length + 3);
  out[0] = 0xef; out[1] = 0xbb; out[2] = 0xbf;
  out.set(inner, 3);
  return out;
}

/**
 * M1-01 领域层先行：编码与换行检测（FR-FILE-003）。
 */
export default function textEncodingTest(): void {
  describe('TextEncodingDetector', () => {
    it('plain_ascii_lf', 0, () => {
      const r = TextEncodingDetector.detect(utf8Of('hello\nworld\n'));
      expect(r.encoding).assertEqual('utf-8');
      expect(r.lineEnding).assertEqual('lf');
      expect(r.validUtf8).assertTrue();
      expect(r.bomOffset).assertEqual(0);
    });

    it('bom_detected', 0, () => {
      const r = TextEncodingDetector.detect(withBom(utf8Of('abc')));
      expect(r.encoding).assertEqual('utf-8-bom');
      expect(r.bomOffset).assertEqual(3);
      expect(r.validUtf8).assertTrue();
    });

    it('crlf_detected', 0, () => {
      const r = TextEncodingDetector.detect(utf8Of('a\r\nb\r\nc'));
      expect(r.lineEnding).assertEqual('crlf');
    });

    it('crlf_dominant_over_mixed', 0, () => {
      const r = TextEncodingDetector.detect(utf8Of('a\nb\r\nc\r\n'));
      expect(r.lineEnding).assertEqual('crlf');
    });

    it('chinese_utf8_valid', 0, () => {
      const r = TextEncodingDetector.detect(utf8Of('你好，鸿蒙！'));
      expect(r.validUtf8).assertTrue();
    });

    it('invalid_utf8_sequence_rejected', 0, () => {
      // 0xC0 后缺续字节
      const bytes = new Uint8Array([0x61, 0xc0, 0x61]);
      expect(TextEncodingDetector.isValidUtf8(bytes)).assertFalse();
    });

    it('invalid_continuation_rejected', 0, () => {
      // 0xE4 后跟非 0x80-0xBF 字节
      const bytes = new Uint8Array([0xe4, 0x61, 0x62]);
      expect(TextEncodingDetector.isValidUtf8(bytes)).assertFalse();
    });

    it('overlong_sequence_rejected', 0, () => {
      // 0xC0 0x80（过短编码的 NUL）应拒绝
      const bytes = new Uint8Array([0xc0, 0x80]);
      expect(TextEncodingDetector.isValidUtf8(bytes)).assertFalse();
    });

    it('empty_file_valid', 0, () => {
      const r = TextEncodingDetector.detect(new Uint8Array(0));
      expect(r.validUtf8).assertTrue();
      expect(r.encoding).assertEqual('utf-8');
      expect(r.lineEnding).assertEqual('lf');
    });

    it('bare_cr_treated_as_lf', 0, () => {
      const r = TextEncodingDetector.detect(utf8Of('a\rb'));
      expect(r.lineEnding).assertEqual('lf');
      expect(r.validUtf8).assertTrue();
    });
  });
}