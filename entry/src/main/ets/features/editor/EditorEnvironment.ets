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

/** Per-mounted-editor platform dependencies and disposable handles; never an observed UI model. */
export class EditorEnvironment {
  disposed: boolean = false;
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
