import { FileRevisionContract, DocumentWriteFormat } from '../../domain/document/DocumentFileAdapter';
import { AppSettings, SettingsValidator } from '../../domain/settings/AppSettings';
import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { mediaquery } from '@kit.ArkUI';
import { EditorBridge } from '../../services/EditorBridge';
import { SaveCoordinator } from '../../services/SaveCoordinator';
import { InternalFileSource } from '../../infrastructure/file/InternalFileSource';
import { ExternalUriFileSource } from '../../infrastructure/file/ExternalUriFileSource';
import { DraftStore } from '../../infrastructure/metadata/DraftStore';
import { MetadataStore } from '../../infrastructure/metadata/MetadataStore';
import { SettingsStore } from '../../infrastructure/metadata/SettingsStore';
import { ReadDocumentResult } from '../../domain/document/DocumentFileAdapter';

/** Per-mounted-editor platform dependencies and disposable handles; never an observed UI model. */
export class EditorEnvironment {
  bridgeMessages: string[] = [];
  bridgeSink: ((message: string) => void) | undefined = undefined;
  disposed: boolean = false;
  openPromptVisible: boolean = false;
  activeSession: string = '';
  appSettings: AppSettings = SettingsValidator.defaults();
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
  get pendingOpenUri(): string { return AppStorage.get<string>('pendingOpenUri') ?? ''; }
  set pendingOpenUri(uri: string) { AppStorage.setOrCreate('pendingOpenUri', uri); }
  ctx: common.UIAbilityContext;
  controller: webview.WebviewController = new webview.WebviewController();
  previewController: webview.WebviewController = new webview.WebviewController();
  bridge: EditorBridge = new EditorBridge();
  internal: InternalFileSource;
  external: ExternalUriFileSource = new ExternalUriFileSource();
  drafts: DraftStore;
  settings: SettingsStore;
  meta: MetadataStore;
  coordinator: SaveCoordinator | undefined = undefined;
  documentRead: Promise<ReadDocumentResult> | undefined = undefined;
  bpListeners: mediaquery.MediaQueryListener[] = [];
  previewTimer: number = -1;
  flushTimer: number = -1;
  saveTimer: number = -1;
  afterFileSheet: (() => void) | undefined = undefined;
  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
    this.internal = new InternalFileSource(ctx);
    this.drafts = new DraftStore(ctx);
    this.settings = new SettingsStore(ctx);
    this.meta = new MetadataStore(ctx);
  }
}
