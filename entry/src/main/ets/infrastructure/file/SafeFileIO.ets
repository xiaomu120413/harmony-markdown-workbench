import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

/** 所有短读/短写都必须显式处理；失败不提交临时文件。 */
export class SafeFileIO {
  /** 部分设备的编码器对空字符串返回 undefined；空文档始终编码为零字节。 */
  static utf8Bytes(content: string): Uint8Array {
    return content.length === 0 ? new Uint8Array(0) : util.TextEncoder.create('utf-8').encodeInto(content);
  }

  static exists(path: string): boolean {
    try { return fs.accessSync(path); }
    catch (e) {
      if ((e as ESObject).code === 13900002) { return false; }
      throw e as Error;
    }
  }

  static readBytes(path: string, limit: number = 32 * 1024 * 1024): Uint8Array {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      return SafeFileIO.readFd(file.fd, limit);
    } finally {
      fs.closeSync(file.fd);
    }
  }

  static readFd(fd: number, limit: number = 32 * 1024 * 1024): Uint8Array {
      const size = fs.statSync(fd).size;
      if (size > limit) {
        throw new Error('文件超过本次操作的大小限制');
      }
      const bytes = new Uint8Array(size);
      let offset = 0;
      while (offset < size) {
        const block = new ArrayBuffer(Math.min(size - offset, 256 * 1024));
        const n = fs.readSync(fd, block);
        if (n <= 0 || n > block.byteLength) {
          throw new Error('文件读取不完整');
        }
        bytes.set(new Uint8Array(block, 0, n), offset);
        offset += n;
      }
      return bytes;
  }

  static writeAll(fd: number, bytes: Uint8Array): void {
    let offset = 0;
    while (offset < bytes.byteLength) {
      const n = fs.writeSync(fd, bytes.slice(offset).buffer);
      if (n <= 0 || n > bytes.byteLength - offset) {
        throw new Error('文件写入不完整');
      }
      offset += n;
    }
  }

  static writeBytes(path: string, bytes: Uint8Array): void {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      SafeFileIO.writeAll(file.fd, bytes);
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file.fd);
    }
  }

  static writeText(path: string, content: string): void {
    SafeFileIO.writeBytes(path, SafeFileIO.utf8Bytes(content));
  }

  /** Picker 目标可能是已有文件。先读备份，写失败尽力恢复；不盲删已有用户文件。 */
  static replaceTarget(path: string, writer: (fd: number) => void): void {
    const before = SafeFileIO.readBytes(path);
    const output = fs.openSync(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    let failed = false;
    try {
      writer(output.fd);
      fs.fsyncSync(output.fd);
    } catch (e) { failed = true; }
    finally { fs.closeSync(output.fd); }
    if (failed) {
      try { SafeFileIO.writeBytes(path, before); }
      catch (e) { throw new Error('目标写入失败，原内容恢复也失败；请保留恢复草稿并更换目标位置'); }
      throw new Error('目标写入失败，已恢复写入前的内容；请更换位置后重试');
    }
  }

  static replaceTextTarget(path: string, content: string): void {
    const bytes = SafeFileIO.utf8Bytes(content);
    SafeFileIO.replaceTarget(path, (fd: number) => SafeFileIO.writeAll(fd, bytes));
  }

  static atomicText(path: string, content: string): void {
    SafeFileIO.atomicBytes(path, SafeFileIO.utf8Bytes(content));
  }

  static atomicBytes(path: string, bytes: Uint8Array): void {
    const temporary = `${path}.tmp`;
    try {
      SafeFileIO.writeBytes(temporary, bytes);
      fs.renameSync(temporary, path);
    } finally {
      if (SafeFileIO.exists(temporary)) {
        fs.unlinkSync(temporary);
      }
    }
  }
}
