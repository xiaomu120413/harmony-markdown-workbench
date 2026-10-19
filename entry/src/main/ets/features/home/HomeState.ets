import { RecentEntry } from '../../domain/document/RecentFileList';
import { DocSearchResult } from '../../domain/document/LibrarySearch';
import { AppTheme } from '../../common/AppTheme';
import { Breakpoint } from '../../common/Breakpoints';

@Observed
export class HomeState {
  compactHeight: boolean = false;
  dropBusy: boolean = false;
  recent: RecentEntry[] = [];
  libraryFiles: string[] = [];
  draftCount: number = 0;
  pickingFile: boolean = false;
  renamingFrom: string = '';
  renameText: string = '';
  trashFiles: string[] = [];
  trashOpen: boolean = false;
  searchQuery: string = '';
  recentCollapsed: boolean = false;
  searchResults: DocSearchResult[] = [];
  searchBusy: boolean = false;
  bp: Breakpoint = 'phone';
  pal: AppTheme = AppTheme.light();
}
