/**
 * 资料库文件名安全校验（FR-FILE-001 / M1-03 验收：文件名校验防止目录穿越和非法路径）。
 * 规则：
 *  - 非空且去掉首尾空白；
 *  - 不允许路径分隔符（/ \）；
 *  - 不允许 .. 序列（防目录穿越）；
 *  - 不允许控制字符（0x00-0x1F）；
 *  - 长度限制（≤ 128 字符）；
 *  - 不允许以点开头（隐藏文件，避免误用）。
 * 纯逻辑，不依赖 @ohos 平台（SDD 11.1）。
 */
export class FileNameValidator {
  static readonly MAX_LENGTH: number = 128;

  static validate(name: string): string | undefined {
    const trimmed = name.trim();
    if (trimmed.length === 0) {
      return '文件名不能为空';
    }
    if (trimmed.length > FileNameValidator.MAX_LENGTH) {
      return `文件名长度不能超过 ${FileNameValidator.MAX_LENGTH} 字符`;
    }
    if (trimmed === '.' || trimmed === '..') {
      return '文件名不能为 . 或 ..';
    }
    if (trimmed.includes('/') || trimmed.includes('\\')) {
      return '文件名不能包含路径分隔符';
    }
    if (trimmed.includes('..')) {
      return '文件名不能包含 ..（防目录穿越）';
    }
    if (trimmed.startsWith('.')) {
      return '文件名不能以点开头';
    }
    for (let i = 0; i < trimmed.length; i++) {
      const code: number = trimmed.charCodeAt(i);
      if (code < 0x20) {
        return '文件名不能包含控制字符';
      }
    }
    return undefined;
  }

  /** 非法时返回错误消息，合法时返回规范化的文件名（去除首尾空白） */
  static sanitizeOrError(name: string): string {
    const err = FileNameValidator.validate(name);
    if (err !== undefined) {
      return err;
    }
    return name.trim();
  }
}