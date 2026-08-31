import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { RecentEntry } from '../../domain/document/RecentFileList';

/**
 * 元数据存储（FR-RECENT / M1-02）。
 * 只存索引（documentId/时间/固定标记），正文绝不写入（ADR-002）。
 * preferences 键：recent（JSON 数组序列化）。
 */
export class MetadataStore {
  private readonly ctx: common.UIAbilityContext;
  private readonly prefName: string = 'hmwb_metadata';
  private readonly keyRecent: string = 'recent';

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  async saveRecent(entries: RecentEntry[]): Promise<void> {
    const prefs = await preferences.getPreferences(this.ctx, this.prefName);
    interface RecentRow {
      id: string;
      at: number;
      pinned: boolean;
    }
    const data: Array<RecentRow> = [];
    for (let i = 0; i < entries.length; i++) {
      const e = entries[i];
      data.push({ id: e.documentId, at: e.lastOpenedAt, pinned: e.pinned });
    }
    await prefs.put(this.keyRecent, JSON.stringify(data));
    await prefs.flush();
  }

  async loadRecent(): Promise<RecentEntry[]> {
    const prefs = await preferences.getPreferences(this.ctx, this.prefName);
    const raw = (await prefs.get(this.keyRecent, '')) as string;
    if (raw.length === 0) {
      return [];
    }
    try {
      let arr: ESObject = JSON.parse(raw);
      const result: RecentEntry[] = [];
      const n = arr.length as number;
      for (let i = 0; i < n; i++) {
        const item: ESObject = arr[i];
        result.push({
          documentId: item.id as string,
          lastOpenedAt: item.at as number,
          pinned: item.pinned as boolean,
        });
      }
      return result;
    } catch (e) {
      // 损坏元数据：返回空（不崩溃；下次保存覆盖）
      return [];
    }
  }
}