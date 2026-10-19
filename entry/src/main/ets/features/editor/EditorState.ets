import { OutlineEntry } from './EditorTypes';
import { FindMatch } from '../../domain/editor/FindReplaceEngine';
import { DocumentSource, FileRevisionContract, DocumentWriteFormat } from '../../domain/document/DocumentFileAdapter';
import { AppTheme } from '../../common/AppTheme';
import { RecentEntry } from '../../domain/document/RecentFileList';
import { Breakpoint } from '../../common/Breakpoints';
import { AppSettings, SettingsValidator, DefaultView } from '../../domain/settings/AppSettings';

@Observed
export class EditorState {
  saveLabel: string = '已保存';
  recoveryLabel: string = '';
  deliveryBusy: boolean = false;
  dropBusy: boolean = false;
  fileHover: boolean = false;
  fileMenuVisible: boolean = false;
  fileSheetVisible: boolean = false;
  fileSheetSection: string = 'root';
  activeToolMenu: string = '';
  openPromptVisible: boolean = false;
  activeSession: string = '';
  pageActive: boolean = true;
  docLength: number = 0;
  docTitle: string = '未命名';
  conflictVisible: boolean = false;
  viewMode: DefaultView = DefaultView.EDIT;
  findVisible: boolean = false;
  findQuery: string = '';
  replaceText: string = '';
  findCase: boolean = false;
  findWord: boolean = false;
  matchCount: number = 0;
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
  appSettings: AppSettings = SettingsValidator.defaults();
  pal: AppTheme = AppTheme.light();
  bp: Breakpoint = 'phone';
  contentWidthVp: number = 1000;
  docTarget: DocumentSource | undefined = undefined;
  expectedRevision: FileRevisionContract = { size: 0, contentHash: '' };
  pendingLoad: string = '';
  retiredDraftId: string = '';
  sessionDraftId: string = `session:${Date.now()}-${Math.floor(Math.random() * 0xffff).toString(16)}`;
  docFormat: DocumentWriteFormat = { encoding: 'utf-8', lineEnding: 'lf' };
  docValidUtf8: boolean = true;
  pendingLoadAt: number = 0;
  webReady: boolean = false;
  previewReady: boolean = false;
  lastPreviewedMd: string = '\u0000';
  findMatches: FindMatch[] = [];
  titleControlsBottom: number = 0;
  titleControlsWidth: number = 0;
  compactHeight: boolean = false;
  get pendingOpenUri(): string { return AppStorage.get<string>('pendingOpenUri') ?? ''; }
  set pendingOpenUri(uri: string) { AppStorage.setOrCreate('pendingOpenUri', uri); }

}
