import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/**
 * 工作台 UI 偏好持久化（B2：侧栏折叠记忆）。
 * 区分用户偏好（sidebarPreferredOpen）与实际展示（由空间策略计算）：
 * 窗口缩小造成的自动折叠不覆盖用户偏好；重新放大后恢复。
 */
export class WorkspaceUiStore {
  private readonly ctx: common.UIAbilityContext;
  private readonly prefName: string = 'hmwb_metadata';
  private readonly sidebarKey: string = 'sidebarPreferredOpen';

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  async loadSidebarPreferredOpen(): Promise<boolean> {
    try {
      const prefs = await preferences.getPreferences(this.ctx, this.prefName);
      const raw = (await prefs.get(this.sidebarKey, true)) as boolean;
      return raw === true;
    } catch (e) {
      return true; // 默认展开
    }
  }

  async saveSidebarPreferredOpen(open: boolean): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(this.ctx, this.prefName);
      await prefs.put(this.sidebarKey, open);
      await prefs.flush();
    } catch (e) {
      // 持久化失败不阻塞交互
    }
  }
}
