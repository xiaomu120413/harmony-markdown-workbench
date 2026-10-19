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

  /**
   * 记录 id 的展示名（V0.2.3 显示修复）：
   *   internal —— "library/周报.md" → "周报.md"；
   *   external —— URI 取最后路径段（file:///docs/a/周报.md → 周报.md）；
   *   兜底原样返回。
   */
  static displayName(id: string): string {
    if (id.startsWith('library/')) {
      return id.substring('library/'.length);
    }
    const path = RecentFileList.identity(id);
    const slash = path.lastIndexOf('/');
    if (slash >= 0 && slash + 1 < path.length) {
      return path.substring(slash + 1);
    }
    return id;
  }

  static identity(id: string): string {
    if (!id.startsWith('file://')) { return id; }
    const path = id.split(/[?#]/)[0];
    try { return decodeURIComponent(path); } catch (e) { return path; }
  }

  static location(id: string): string {
    if (id.startsWith('library/')) { return '我的文档 · 应用内'; }
    const path = RecentFileList.identity(id).replace(/^file:\/\//, '');
    const slash = path.lastIndexOf('/');
    const parent = (slash >= 0 ? path.substring(0, slash) : path).replace(/^docs\/storage\/Users\/currentUser/, '个人文件');
    return `外部 · ${parent}`;
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
    const existing = this.entries.find((e: RecentEntry): boolean => RecentFileList.identity(e.documentId) === RecentFileList.identity(documentId));
    if (existing !== undefined) {
      existing.lastOpenedAt = at;
      existing.documentId = documentId;
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
    const existing = this.entries.find((e: RecentEntry): boolean => RecentFileList.identity(e.documentId) === RecentFileList.identity(documentId));
    if (existing !== undefined) {
      existing.pinned = pinned;
    }
  }

  remove(documentId: string): void {
    this.entries = this.entries.filter((e: RecentEntry): boolean => RecentFileList.identity(e.documentId) !== RecentFileList.identity(documentId));
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
    const seen = new Map<string, RecentEntry>();
    const unique: RecentEntry[] = [];
    const sorted = this.snapshot();
    for (const e of sorted) {
      if (/\/data\/storage\/el2\/base\/(?:haps\/entry\/)?cache\//.test(e.documentId)) { continue; }
      const key = RecentFileList.identity(e.documentId);
      const existing = seen.get(key);
      if (existing === undefined) {
        const item: RecentEntry = { documentId: e.documentId, lastOpenedAt: e.lastOpenedAt, pinned: e.pinned };
        seen.set(key, item);
        unique.push(item);
      } else if (e.pinned) { existing.pinned = true; }
    }
    this.entries = unique;
    this.evict();
  }
}
