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
  revision: FileRevisionContract;
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
  write(source: DocumentSource, content: string, expectedRevision: FileRevisionContract): Promise<WriteDocumentResult>;
  stat(source: DocumentSource): Promise<FileRevisionContract>;
  canPersistAccess(source: DocumentSource): Promise<boolean>;
  delete?(source: DocumentSource): Promise<void>;
}