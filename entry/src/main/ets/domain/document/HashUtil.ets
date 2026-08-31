/**
 * 简单内容哈希（djb2）。契约测试与适配器共用，
 * 生产实现可在 M4 升级为平台安全哈希（@ohos.security.cryptoFramework）。
 * 纯逻辑，可本地单测。
 */
export class HashUtil {
  static of(s: string): string {
    let h = 5381;
    for (let i = 0; i < s.length; i++) {
      h = ((h << 5) + h + s.charCodeAt(i)) | 0;
    }
    return `h${h >>> 0}`;
  }
}