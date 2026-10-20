import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { RecoveryDraft } from '../../domain/recovery/DraftDecision';
import { HashUtil } from '../../domain/document/HashUtil';
import { SafeFileIO } from '../file/SafeFileIO';

/**
 * 草稿检查点存储（FR-SAVE-003 / M4-01）。
 * 路径：filesDir/drafts/<hash>.json（hash = 文档 id 的哈希，避免路径穿越）。
 * 正文作为恢复数据只存在于应用私有目录（ADR-002：preferences 不写正文）。
 */
export class DraftStore {
  private readonly draftsDir: string;
  // 与 AppScope/app.json5 的 versionName 保持一致（宿主机测试会校验）。
  private readonly appVersion: string = '1.0.0';

  constructor(ctx: common.UIAbilityContext) {
    this.draftsDir = `${ctx.filesDir}/drafts`;
  }

  /** 保存检查点（供 SaveCoordinator.saveCheckpoint 调用） */
  save(documentId: string, fingerprint: string, baseSize: number, baseHash: string, content: string): void {
    try {
      fs.mkdirSync(this.draftsDir);
    } catch (e) {
      const err: string = String(e);
      if (!err.includes('exist')) {
        // 目录创建失败由 openSync 暴露
      }
    }
    const draft: RecoveryDraft = {
      documentId: documentId,
      sourceFingerprint: fingerprint,
      baseRevision: { size: baseSize, contentHash: baseHash },
      content: content,
      updatedAt: Date.now(),
      appVersion: this.appVersion,
    };
    const path = `${this.draftsDir}/${HashUtil.of(documentId)}.json`;
    SafeFileIO.atomicText(path, JSON.stringify(draft));
  }

  /** 读取检查点（恢复决策输入）；无草稿或损坏返回 undefined（不崩溃） */
  load(documentId: string): RecoveryDraft | undefined {
    const path = `${this.draftsDir}/${HashUtil.of(documentId)}.json`;
    let raw: string = '';
    try {
      const decoder = util.TextDecoder.create('utf-8');
      // JSON 转义后可能比正文更大，不能套用普通文档的 32MiB 默认限制。
      raw = decoder.decodeToString(SafeFileIO.readBytes(path, Number.MAX_SAFE_INTEGER));
    } catch (e) {
      return undefined;
    }
    if (raw.length === 0) {
      return undefined;
    }
    try {
      let obj: ESObject = JSON.parse(raw);
      const draft: RecoveryDraft = {
        documentId: obj.documentId as string,
        sourceFingerprint: obj.sourceFingerprint as string,
        baseRevision: {
          size: (obj.baseRevision as ESObject).size as number,
          contentHash: (obj.baseRevision as ESObject).contentHash as string,
        },
        content: obj.content as string,
        updatedAt: obj.updatedAt as number,
        appVersion: obj.appVersion as string,
      };
      return draft;
    } catch (e) {
      return undefined;
    }
  }

  /** 删除检查点（保存成功后清除冗余草稿） */
  remove(documentId: string): void {
    const path = `${this.draftsDir}/${HashUtil.of(documentId)}.json`;
    try {
      fs.unlinkSync(path);
    } catch (e) {
      // 不存在即视为已清理
    }
  }

  /** 枚举全部检查点（M4-04 恢复入口；损坏草稿返回唯一幸存字段以隔离展示） */
  listAll(): Array<RecoveryDraft> {
    const out: Array<RecoveryDraft> = [];
    let names: string[] = [];
    try {
      names = fs.listFileSync(this.draftsDir);
    } catch (e) {
      return out;
    }
    for (let i = 0; i < names.length; i++) {
      const n = names[i];
      if (!n.endsWith('.json')) {
        continue;
      }
      const id = n.substring(0, n.length - 5);
      const draft = this.loadByHash(id);
      if (draft !== undefined) {
        out.push(draft);
      }
    }
    return out;
  }

  private loadByHash(hash: string): RecoveryDraft | undefined {
    const path = `${this.draftsDir}/${hash}.json`;
    let raw: string = '';
    try {
      const decoder = util.TextDecoder.create('utf-8');
      raw = decoder.decodeToString(SafeFileIO.readBytes(path, Number.MAX_SAFE_INTEGER));
    } catch (e) {
      return undefined;
    }
    if (raw.length === 0) {
      return undefined;
    }
    try {
      let obj: ESObject = JSON.parse(raw);
      const draft: RecoveryDraft = {
        documentId: obj.documentId as string,
        sourceFingerprint: obj.sourceFingerprint as string,
        baseRevision: {
          size: (obj.baseRevision as ESObject).size as number,
          contentHash: (obj.baseRevision as ESObject).contentHash as string,
        },
        content: obj.content as string,
        updatedAt: obj.updatedAt as number,
        appVersion: obj.appVersion as string,
      };
      return draft;
    } catch (e) {
      return undefined;
    }
  }
}
