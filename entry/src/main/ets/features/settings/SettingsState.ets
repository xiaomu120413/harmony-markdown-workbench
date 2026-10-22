import { ThemeMode, DefaultView } from '../../domain/settings/AppSettings';
import { AppTheme } from '../../common/AppTheme';

@Observed
export class SettingsState {
  themeMode: ThemeMode = ThemeMode.SYSTEM;
  fontSize: number = 15;
  wrap: boolean = true;
  lineNumbers: boolean = true;
  autoSave: boolean = true;
  defaultView: DefaultView = DefaultView.EDIT;
  draftCount: number = 0;
  pal: AppTheme = AppTheme.light();
}
