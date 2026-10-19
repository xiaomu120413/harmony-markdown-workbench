import { common } from '@kit.AbilityKit';
import { mediaquery } from '@kit.ArkUI';
import { MetadataStore } from '../../infrastructure/metadata/MetadataStore';
import { InternalFileSource } from '../../infrastructure/file/InternalFileSource';
import { DraftStore } from '../../infrastructure/metadata/DraftStore';
import { SettingsStore } from '../../infrastructure/metadata/SettingsStore';

export class HomeEnvironment {
  active: boolean = true;
  get pendingOpenUri(): string { return AppStorage.get<string>('pendingOpenUri') ?? ''; }
  set pendingOpenUri(uri: string) { AppStorage.setOrCreate('pendingOpenUri', uri); }
  ctx: common.UIAbilityContext;
  meta: MetadataStore;
  fileSource: InternalFileSource;
  draftStore: DraftStore;
  settings: SettingsStore;
  bpListeners: mediaquery.MediaQueryListener[] = [];
  searchTimer: number = -1;
  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
    this.meta = new MetadataStore(ctx);
    this.fileSource = new InternalFileSource(ctx);
    this.draftStore = new DraftStore(ctx);
    this.settings = new SettingsStore(ctx);
  }
}
