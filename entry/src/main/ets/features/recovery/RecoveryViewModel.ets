import { MuLogger } from '../../common/MuLogger';
import { common } from '@kit.AbilityKit';
import { DraftStore } from '../../infrastructure/metadata/DraftStore';
import { MetadataStore } from '../../infrastructure/metadata/MetadataStore';
import { RecentFileList } from '../../domain/document/RecentFileList';
import { InternalFileSource } from '../../infrastructure/file/InternalFileSource';
import { DraftDecisionEvaluator, RecoveryDecision } from '../../domain/recovery/DraftDecision';
import { FileRevisionContract, InternalSource, WriteFailResult } from '../../domain/document/DocumentFileAdapter';
import { FileRevision } from '../../domain/document/FileRevision';
import { HashUtil } from '../../domain/document/HashUtil';
import { DocumentNamer } from '../../domain/document/DocumentNamer';
import { SettingsStore } from '../../infrastructure/metadata/SettingsStore';
import { AppTheme } from '../../common/AppTheme';

import { promptAction } from '@kit.ArkUI';
import { RecoveryState, DraftRow } from './RecoveryState';
export class RecoveryViewModel {
  private active: boolean = true;
  private ctx: common.UIAbilityContext;
  private store: DraftStore;
  private internal: InternalFileSource;
  private meta: MetadataStore;
  state: RecoveryState;
  constructor(state: RecoveryState, ctx: common.UIAbilityContext) {
    this.state = state; this.ctx = ctx;
    this.store = new DraftStore(ctx); this.internal = new InternalFileSource(ctx); this.meta = new MetadataStore(ctx);
  }
  dispose(): void { this.active = false; }
  documentName(fingerprint: string): string {
    return fingerprint === 'session:new' ? '未保存的新文档' :
      RecentFileList.displayName(fingerprint.replace('internal:library/', 'library/'));
  }
  /** M5-01：恢复写回/另存副本后同步最近列表元数据（失败不阻塞正文） */
  private async trackRecent(relativePath: string): Promise<void> {
    try {
      const entries = await this.meta.loadRecent();
      const list = new RecentFileList(entries);
      list.touch(relativePath, Date.now());
      await this.meta.saveRecent(list.snapshot());
    } catch (e) {
      // 元数据失败不影响正文
    }
  }

  async load(): Promise<void> {
    await this.loadTheme();
    await this.reload();
  }

  async loadTheme(): Promise<void> {
    try {
      const st = await new SettingsStore(this.ctx).load();
      if (!this.active) { return; }
      this.state.pal = AppTheme.of(AppTheme.isDark(st.theme, this.ctx.config?.colorMode));
    } catch (e) {
      // 主题读取失败按浅色
    }
  }

  private async reload(): Promise<void> {
    const all = this.store.listAll();
    const out: Array<DraftRow> = [];
    for (let i = 0; i < all.length; i++) {
      const d = all[i];
      const diskRev = await this.diskRevisionOf(d.sourceFingerprint);
      const decision = DraftDecisionEvaluator.decide(d, diskRev, HashUtil.of(d.content));
      let name: string;
      switch (decision) {
        case RecoveryDecision.NO_DRAFT:
        case RecoveryDecision.DISCARD_REDUNDANT:
          name = '冗余可清理';
          break;
        case RecoveryDecision.RESTORE_DRAFT:
          name = '可恢复';
          break;
        default:
          name = '冲突（勿自动覆盖）';
          break;
      }
      out.push({ draft: d, decisionName: name, decision: decision, diskChanged: diskRev !== undefined && (diskRev as FileRevision).contentHash !== d.baseRevision.contentHash });
    }
    if (!this.active) { return; }
    this.state.rows = out;
    MuLogger.info(`[恢复] ${out.length} 个检查点`);
  }

  /** 磁盘 revision：internal 可 stat；external（临时授权可能已失效）→ undefined */
  private async diskRevisionOf(fingerprint: string): Promise<FileRevision | undefined> {
    if (!fingerprint.startsWith('internal:')) {
      return undefined;
    }
    const rel = fingerprint.substring('internal:'.length);
    try {
      const src: InternalSource = { kind: 'internal', relativePath: rel };
      const c = await this.internal.stat(src);
      const rev: FileRevision = { size: c.size, contentHash: c.contentHash, modifiedTime: c.modifiedTime };
      return rev;
    } catch (e) {
      return undefined;
    }
  }

  fmtTime(ms: number): string {
    const d = new Date(ms);
    const hour = `${d.getHours()}`.padStart(2, '0');
    const minute = `${d.getMinutes()}`.padStart(2, '0');
    return `${d.getMonth() + 1}/${d.getDate()} ${hour}:${minute}`;
  }

  /** 恢复：草稿内容写回源文档（磁盘==基线才写，写前复核决策） */
  async restoreRow(row: DraftRow): Promise<void> {
    if (row.decision !== RecoveryDecision.RESTORE_DRAFT) {
      MuLogger.info(`[恢复] 决策为 ${row.decisionName}，跳过自动覆盖`);
      promptAction.showToast({ message: '磁盘已有变化，请使用「另存副本」' });
      return;
    }
    const d = row.draft;
    if (!d.sourceFingerprint.startsWith('internal:')) {
      // A3：会话草稿（session:new）与外部草稿均无原位写回目标 → 另存副本
      MuLogger.info('[恢复] 仅内部文档支持自动写回；外部/会话草稿请用另存副本');
      promptAction.showToast({ message: '请使用「另存副本」保存到资料库' });
      return;
    }
    const rel = d.sourceFingerprint.substring('internal:'.length);
    const src: InternalSource = { kind: 'internal', relativePath: rel };
    try {
      const base: FileRevisionContract = {
        size: d.baseRevision.size,
        contentHash: d.baseRevision.contentHash,
        modifiedTime: d.baseRevision.modifiedTime,
      };
      const result = await this.internal.write(src, d.content, base);
      if (result.ok) {
        this.store.remove(d.documentId);
        this.trackRecent(rel);
        MuLogger.info(`[恢复] 已写回 ${rel} 并清除草稿`);
      } else {
        MuLogger.info(`[恢复] 写回冲突/失败：${(result as WriteFailResult).message}（请改用另存副本）`);
        promptAction.showToast({ message: '写回失败，请使用「另存副本」' });
      }
    } catch (e) {
      MuLogger.info(`[恢复] 写回异常：${JSON.stringify(e)}`);
    }
    await this.reload();
  }

  /** 另存副本：草稿 → 资料库新文档，随后清除草稿（内容已有可靠副本） */
  async saveCopy(row: DraftRow): Promise<void> {
    const d = row.draft;
    const name = DocumentNamer.derive(d.content, this.internal.listLibrary());
    const rel = `library/${name}`;
    const src: InternalSource = { kind: 'internal', relativePath: rel };
    try {
      const result = await this.internal.write(src, d.content, { size: 0, contentHash: '' });
      if (result.ok) {
        this.store.remove(d.documentId);
        this.trackRecent(rel);
        MuLogger.info(`[副本] 已保存 ${rel} 并清除草稿`);
      } else {
        MuLogger.info(`[副本] 失败：${(result as WriteFailResult).message}`);
        promptAction.showToast({ message: '另存副本失败' });
      }
    } catch (e) {
      MuLogger.info(`[副本] 异常：${JSON.stringify(e)}`);
    }
    await this.reload();
  }

  /** 清理冗余/放弃草稿（操作有明确两次意图：行内按钮文本即确认） */
  discardRow(row: DraftRow): void {
    this.store.remove(row.draft.documentId);
    MuLogger.info(`[清理] 已删除草稿 ${row.draft.documentId}`);
    this.reload();
  }

}
