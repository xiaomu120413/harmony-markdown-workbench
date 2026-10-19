import { RecoveryDecision, RecoveryDraft } from '../../domain/recovery/DraftDecision';
import { AppTheme } from '../../common/AppTheme';
/** 展示行：草稿 + 决策 */
export interface DraftRow {
  draft: RecoveryDraft;
  decisionName: string;
  decision: RecoveryDecision;
  diskChanged: boolean;
}

@Observed
export class RecoveryState {
  rows: DraftRow[] = [];
  pal: AppTheme = AppTheme.light();
}
