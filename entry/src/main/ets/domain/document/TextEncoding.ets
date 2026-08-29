/**
 * 文本编码与换行检测（FR-FILE-003）。
 * - 读取时识别 UTF-8 BOM 与 LF/CRLF；
 * - 非 UTF-8（无效序列）提示，不静默乱码；
 * - 保存时保持原换行风格（调用方依据本结果）。
 * 纯逻辑，可本地单测。
 */
export type TextEncodingKind = 'utf-8' | 'utf-8-bom';
export type LineEndingKind = 'lf' | 'crlf';

export interface TextEncodingResult {
  encoding: TextEncodingKind;
  lineEnding: LineEndingKind;
  validUtf8: boolean;
  /** 去掉 BOM 后的内容字节偏移（读取时跳过 BOM） */
  bomOffset: number;
}

const UTF8_BOM: number[] = [0xef, 0xbb, 0xbf];

/**
 * 基于字节序列检测编码/换行。
 * @param bytes 文件原始字节
 * @param hasTrailing 是否允许不完整的多字节序列（读取中段检测时为 true）
 */
export class TextEncodingDetector {
  static detect(bytes: Uint8Array): TextEncodingResult {
    let bomOffset = 0;
    let encoding: TextEncodingKind = 'utf-8';
    if (bytes.length >= 3 &&
      bytes[0] === UTF8_BOM[0] && bytes[1] === UTF8_BOM[1] && bytes[2] === UTF8_BOM[2]) {
      bomOffset = 3;
      encoding = 'utf-8-bom';
    }

    let crlf = 0;
    let lf = 0;
    let i = bomOffset;
    while (i < bytes.length) {
      const b = bytes[i];
      if (b === 0x0d) {
        if (i + 1 < bytes.length && bytes[i + 1] === 0x0a) {
          crlf++;
          i += 2;
          continue;
        }
        // 孤立 CR：计为换行（尽量保持原状按 lf 处理）
        i++;
        continue;
      }
      if (b === 0x0a) {
        lf++;
      }
      i++;
    }
    const lineEnding: LineEndingKind = crlf > lf ? 'crlf' : 'lf';

    return {
      encoding: encoding,
      lineEnding: lineEnding,
      validUtf8: TextEncodingDetector.isValidUtf8(bytes, bomOffset),
      bomOffset: bomOffset,
    };
  }

  /**
   * 简化 UTF-8 合法性检查（FR-FILE-003：非 UTF-8 不静默乱码）。
   * 覆盖：ASCII、2/3/4 字节序列、过短序列、非法续字节、超范围编码。
   */
  static isValidUtf8(bytes: Uint8Array, start: number = 0): boolean {
    let i = start;
    const n = bytes.length;
    while (i < n) {
      const b = bytes[i];
      if (b < 0x80) {
        i++;
        continue;
      }
      let len = 0;
      let codePoint = 0;
      if ((b & 0xe0) === 0xc0) {
        len = 2;
        codePoint = b & 0x1f;
      } else if ((b & 0xf0) === 0xe0) {
        len = 3;
        codePoint = b & 0x0f;
      } else if ((b & 0xf8) === 0xf0) {
        len = 4;
        codePoint = b & 0x07;
      } else {
        return false; // 非法首字节（0x80-0xBF 或 0xF8+）
      }
      if (i + len > n) {
        return false; // 序列不完整
      }
      for (let j = 1; j < len; j++) {
        const c = bytes[i + j];
        if ((c & 0xc0) !== 0x80) {
          return false; // 非法续字节
        }
        codePoint = (codePoint << 6) | (c & 0x3f);
      }
      // 过短编码（overlong）与超范围
      if (len === 2 && codePoint < 0x80) {
        return false;
      }
      if (len === 3 && codePoint < 0x800) {
        return false;
      }
      if (len === 4 && (codePoint < 0x10000 || codePoint > 0x10ffff)) {
        return false;
      }
      i += len;
    }
    return true;
  }
}