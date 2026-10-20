import { SaveState, SaveStateMachine } from '../../domain/recovery/SaveStateMachine';
import { FindMatch } from '../../domain/editor/FindReplaceEngine';
import { DocumentSource } from '../../domain/document/DocumentFileAdapter';
import { AppTheme } from '../../common/AppTheme';
import { RecentEntry } from '../../domain/document/RecentFileList';
import { Breakpoint } from '../../common/Breakpoints';
import { DefaultView } from '../../domain/settings/AppSettings';

export interface OutlineEntry { level: number; text: string; from: number; to: number; }

@Observed
export class EditorState {
  saveState: SaveState = SaveState.CLEAN;
  recoveryLabel: string = '';
  deliveryBusy: boolean = false;
  dropBusy: boolean = false;
  fileHover: boolean = false;
  fileMenuVisible: boolean = false;
  fileSheetVisible: boolean = false;
  fileSheetSection: string = 'root';
  docLength: number = 0;
  docTitle: string = '未命名';
  get conflictVisible(): boolean { return this.saveState === SaveState.CONFLICT; }
  viewMode: DefaultView = DefaultView.EDIT;
  findVisible: boolean = false;
  findQuery: string = '';
  replaceText: string = '';
  findCase: boolean = false;
  findWord: boolean = false;
  get matchCount(): number { return this.findMatches.length; }
  matchIndex: number = -1;
  outlineVisible: boolean = false;
  outlineEntries: OutlineEntry[] = [];
  cursorLine: number = 1;
  cursorCol: number = 1;
  loadState: 'loading' | 'ready' | 'loadFailed' | 'accessExpired' = 'ready';
  loadFailure: string = '';
  sidebarVisible: boolean = false;
  sidebarRecent: RecentEntry[] = [];
  sidebarLibrary: string[] = [];
  pal: AppTheme = AppTheme.light();
  bp: Breakpoint = 'phone';
  contentWidthVp: number = 1000;
  docTarget: DocumentSource | undefined = undefined;
  findMatches: FindMatch[] = [];
  titleControlsBottom: number = 0;
  titleControlsWidth: number = 0;
  compactHeight: boolean = false;
  get saveLabel(): string {
    if (this.loadState === 'loading') { return '正在打开'; }
    if (this.loadState !== 'ready') { return '未打开'; }
    return SaveStateMachine.label(this.saveState);
  }
}
