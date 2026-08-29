import { describe, expect, it } from '@ohos/hypium';
import { FileNameValidator } from '../main/ets/domain/document/FileNameValidator';

/**
 * M1-03 领域层先行：文件名校验（防目录穿越/非法路径，FR-FILE-001 验收）。
 */
export default function fileNameValidatorTest(): void {
  describe('FileNameValidator', () => {
    it('accepts_normal_name', 0, () => {
      expect(FileNameValidator.validate('README.md')).assertUndefined();
      expect(FileNameValidator.sanitizeOrError(' 笔记.md ')).assertEqual('笔记.md');
    });

    it('rejects_empty', 0, () => {
      expect(FileNameValidator.validate('')).assertEqual('文件名不能为空');
      expect(FileNameValidator.validate('   ')).assertEqual('文件名不能为空');
    });

    it('rejects_path_separators', 0, () => {
      expect(FileNameValidator.validate('a/b.md')).assertEqual('文件名不能包含路径分隔符');
      expect(FileNameValidator.validate('a\\b.md')).assertEqual('文件名不能包含路径分隔符');
    });

    it('rejects_dotdot_traversal', 0, () => {
      expect(FileNameValidator.validate('..')).assertEqual('文件名不能为 . 或 ..');
      expect(FileNameValidator.validate('../evil.md')).assertEqual('文件名不能包含路径分隔符');
      expect(FileNameValidator.validate('a..b.md')).assertEqual('文件名不能包含 ..（防目录穿越）');
    });

    it('rejects_dot_prefix_hidden', 0, () => {
      expect(FileNameValidator.validate('.hidden.md')).assertEqual('文件名不能以点开头');
    });

    it('rejects_control_chars', 0, () => {
      expect(FileNameValidator.validate('bad\u0000name')).assertEqual('文件名不能包含控制字符');
    });

    it('rejects_too_long', 0, () => {
      const long = 'x'.repeat(129);
      expect(FileNameValidator.validate(long)).assertEqual('文件名长度不能超过 128 字符');
    });
  });
}