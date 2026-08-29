/**
 * 最近文件列表领域逻辑（FR-RECENT / SDD 5.5）。
 * - 默认最多 30 条，固定文件不受淘汰影响；
 * - 按最近打开时间倒序；
 * - 正文绝不写入元数据（ADR-002），本层只管理记录 id 与时间。
 * 纯逻辑，不依赖 @ohos 平台（SDD 11.1）。
 */
export interface RecentEntry {
  documentId: string;
  lastOpenedAt: number;
  pinned: boolean;
}

export const RECENT_LIMIT: number = 30;

export class RecentFileList {
  private entries: RecentEntry[] = [];

  constructor(initial?: RecentEntry[]) {
    if (initial !== undefined) {
      this.entries = initial.slice();
      this.normalize();
    }
  }

  get size(): number {
    return this.entries.length;
  }

  /** 按最近打开时间倒序（固定文件在前不强制，排序仍按时间；淘汰时保护固定项） */
  snapshot(): RecentEntry[] {
    const sorted: RecentEntry[] = this.entries.slice().sort((a: RecentEntry, b: RecentEntry): number => {
      return b.lastOpenedAt - a.lastOpenedAt;
    });
    return sorted;
  }

  /** 打开/顶置一条记录（不存在则插入，存在则更新时间） */
  touch(documentId: string, at: number, pinned: boolean = false): void {
    const existing = this.entries.find((e: RecentEntry): boolean => e.documentId === documentId);
    if (existing !== undefined) {
      existing.lastOpenedAt = at;
      if (pinned) {
        existing.pinned = true;
      }
    } else {
      this.entries.push({ documentId: documentId, lastOpenedAt: at, pinned: pinned });
    }
    this.evict();
  }

  /** 固定/取消固定 */
  setPinned(documentId: string, pinned: boolean): void {
    const existing = this.entries.find((e: RecentEntry): boolean => e.documentId === documentId);
    if (existing !== undefined) {
      existing.pinned = pinned;
    }
  }

  remove(documentId: string): void {
    this.entries = this.entries.filter((e: RecentEntry): boolean => e.documentId !== documentId);
  }

  /** 淘汰：超过上限时移除最旧的未固定项（固定文件不受淘汰影响，FR-RECENT） */
  private evict(): void {
    if (this.entries.length <= RECENT_LIMIT) {
      return;
    }
    const sorted = this.entries.slice().sort((a: RecentEntry, b: RecentEntry): number => {
      return a.lastOpenedAt - b.lastOpenedAt;
    });
    let toRemove = this.entries.length - RECENT_LIMIT;
    for (const e of sorted) {
      if (toRemove <= 0) {
        break;
      }
      if (!e.pinned) {
        this.remove(e.documentId);
        toRemove--;
      }
    }
    // 极端情况：全是固定文件且超限 → 保留上限内最旧的固定项
    if (this.entries.length > RECENT_LIMIT) {
      const all = this.entries.slice().sort((a: RecentEntry, b: RecentEntry): number => {
        return a.lastOpenedAt - b.lastOpenedAt;
      });
      this.entries = all.slice(all.length - RECENT_LIMIT);
    }
  }

  private normalize(): void {
    // 去重 + 时间排序修正（构造输入可能无序）
    const seen = new Set<string>();
    const unique: RecentEntry[] = [];
    const sorted = this.snapshot();
    for (const e of sorted) {
      if (!seen.has(e.documentId)) {
        seen.add(e.documentId);
        unique.push(e);
      }
    }
    this.entries = unique;
    this.evict();
  }
}