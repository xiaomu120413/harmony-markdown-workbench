/**
 * 文件来源模型（SDD 5.1 / 8.2）。
 */
export interface InternalSource {
  kind: 'internal';
  relativePath: string;
}

export interface ExternalSource {
  kind: 'external';
  uri: string;
  displayName: string;
}

export type DocumentSource = InternalSource | ExternalSource;

/**
 * 文件适配器契约（SDD 8.2）。
 * 内部（应用私有目录）与外部（URI 权限）适配器必须通过同一套契约测试（SDD 15.2）。
 * 领域层只定义接口，实现位于 infrastructure/（依赖 @ohos 平台能力）。
 */
export interface FileRevisionContract {
  size: number;
  modifiedTime?: number;
  contentHash: string;
}

export interface ReadDocumentResult {
  content: string;
  encoding: 'utf-8' | 'utf-8-bom';
  lineEnding: 'lf' | 'crlf';
  validUtf8: boolean;
  revision: FileRevisionContract;
}

/** 写入格式（A4：编辑器正文为 LF 规范层，落盘按原格式还原） */
export interface DocumentWriteFormat {
  encoding: 'utf-8' | 'utf-8-bom';
  lineEnding: 'lf' | 'crlf';
}

export type WriteFailureReason = 'permission' | 'conflict' | 'io' | 'not_found';

export interface WriteOkResult {
  ok: true;
  revision: FileRevisionContract;
}

export interface WriteFailResult {
  ok: false;
  reason: WriteFailureReason;
  message: string;
}

export type WriteDocumentResult = WriteOkResult | WriteFailResult;

export interface DocumentFileAdapter {
  read(source: DocumentSource): Promise<ReadDocumentResult>;
  write(source: DocumentSource, content: string, expectedRevision: FileRevisionContract, format?: DocumentWriteFormat): Promise<WriteDocumentResult>;
  stat(source: DocumentSource): Promise<FileRevisionContract>;
  canPersistAccess(source: DocumentSource): Promise<boolean>;
  delete?(source: DocumentSource): Promise<void>;
}

/**
 * 正文规范化与格式还原（A4 编码换行契约，纯逻辑）。
 * 两层模型：编辑器正文一律 LF、无 BOM；落盘时按 DocumentWriteFormat 还原。
 * 读写两侧（基线哈希与预检哈希）都必须用 normalizeToLf 后的文本，
 * 保证 BOM/CRLF 文件不误报冲突（A4-03）。
 */
export class TextRoundtrip {
  /** CRLF/CR → LF（编辑器规范层） */
  static normalizeToLf(text: string): string {
    return text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  }

  /** LF → 目标换行风格 + BOM 前缀（落盘字节层的字符串形态；\uFEFF 编码为 EF BB BF） */
  static applyFormat(text: string, format: DocumentWriteFormat): string {
    const lfOnly = TextRoundtrip.normalizeToLf(text);
    const withEnding = format.lineEnding === 'crlf' ? lfOnly.replace(/\n/g, '\r\n') : lfOnly;
    const withBom = format.encoding === 'utf-8-bom' ? `\uFEFF${withEnding}` : withEnding;
    return withBom;
  }
}