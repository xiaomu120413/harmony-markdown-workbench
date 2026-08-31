import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';
import { SaveState, SaveStateMachine } from '../domain/recovery/SaveStateMachine';
import { MarkdownCommands, MarkdownCommandName, TextRange, TextTransformResult } from '../domain/editor/MarkdownCommands';
import { EditorBridge } from '../services/EditorBridge';
import { SaveCoordinator, SaveCoordinatorDeps } from '../services/SaveCoordinator';
import { DocumentFileAdapter, DocumentSource, InternalSource, ExternalSource, FileRevisionContract, WriteDocumentResult } from '../domain/document/DocumentFileAdapter';
import { InternalFileSource } from '../infrastructure/file/InternalFileSource';
import { ExternalUriFileSource } from '../infrastructure/file/ExternalUriFileSource';
import { DraftStore } from '../infrastructure/metadata/DraftStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-EDITOR';

/** 桥消息队列（ArkWeb jsProxy 回调线程不能操作组件 this——M0-03 R-16 结论） */
let pendingBridge: Array<string> = [];
let bridgeSink: ((msg: string) => void) | undefined = undefined;

function editorBridgeSend(raw: string): void {
  pendingBridge.push(raw);
}

/** 路由参数形状（M5-01：name=内部相对路径 / uri=外部文档 URI） */
interface RouteParams {
  name?: string;
  uri?: string;
}

/**
 * SaveCoordinator 依赖适配（ArkTS：接口方法成员不能由对象字面量属性函数满足，
 * 以显式 class 注入组件闭包）。
 */
class EditorPageDeps implements SaveCoordinatorDeps {
  private readonly snapshotImpl: () => Promise<string>;
  private readonly checkpointImpl: (c: string) => Promise<void>;
  private readonly persistImpl: (c: string) => Promise<WriteDocumentResult>;

  constructor(
    snapshotImpl: () => Promise<string>,
    checkpointImpl: (c: string) => Promise<void>,
    persistImpl: (c: string) => Promise<WriteDocumentResult>,
  ) {
    this.snapshotImpl = snapshotImpl;
    this.checkpointImpl = checkpointImpl;
    this.persistImpl = persistImpl;
  }

  getSnapshot(): Promise<string> {
    return this.snapshotImpl();
  }

  saveCheckpoint(content: string): Promise<void> {
    return this.checkpointImpl(content);
  }

  persist(content: string): Promise<WriteDocumentResult> {
    return this.persistImpl(content);
  }
}

/**
 * M2/M4 正式编辑器页（CM6.x 运行时 + 桥模式 + SaveCoordinator 持久化）。
 * 组件：编辑器 + Markdown 快捷栏（领域命令变换）+ 手动/自动保存状态。
 * 路由参数（M5-01）：name=内部相对路径（library/..）或 uri=外部文档 URI。
 */
@Entry
@Component
struct EditorPage {
  @State log: string = '';
  @State saveLabel: string = '已保存';
  @State docLength: number = 0;
  @State docTitle: string = '未命名';
  @State conflictVisible: boolean = false;
  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: EditorBridge = new EditorBridge();
  private internal: InternalFileSource = new InternalFileSource(getContext(this) as common.UIAbilityContext);
  private external: ExternalUriFileSource = new ExternalUriFileSource();
  private drafts: DraftStore = new DraftStore(getContext(this) as common.UIAbilityContext);
  private coordinator: SaveCoordinator | undefined = undefined;
  private docTarget: DocumentSource | undefined = undefined;
  private expectedRevision: FileRevisionContract = { size: 0, contentHash: '' };
  private pendingLoad: string = '';
  private webReady: boolean = false;
  private flushTimer: number = -1;
  private saveTimer: number = -1;

  private append(line: string): void {
    this.log = `${line}\n---\n${this.log}`;
    hilog.info(DOMAIN, TAG, '%{public}s', line);
  }

  aboutToAppear(): void {
    // 编排器延迟创建：deps 闭包依赖组件方法（字段初始化器内不能引用 this）
    this.coordinator = new SaveCoordinator(new EditorPageDeps(
      () => this.runJsValue('window.__editorApi.getSnapshot();'),
      (content: string) => this.doSaveCheckpoint(content),
      (content: string) => this.doPersist(content),
    ));
    bridgeSink = (raw: string): void => {
      const env = this.bridge.parseEvent(raw);
      if (env === undefined) {
        return;
      }
      if (env.type === 'edit') {
        // 用户输入（打字/粘贴/IME）：进入 DIRTY 并调度防抖保存
        const len = env.payload.len as number | undefined;
        if (len !== undefined) {
          this.docLength = len;
        }
        const c = this.coordinator;
        if (c !== undefined) {
          c.onEdit(Date.now());
          this.saveLabel = SaveStateMachine.label(c.state);
        }
        return;
      }
      if (!this.bridge.isFirstResponse(env.id)) {
        return;
      }
      this.append(`[event] ${env.type}`);
    };
    this.flushTimer = setInterval(() => {
      const drained = pendingBridge.slice();
      pendingBridge = [];
      for (let i = 0; i < drained.length; i++) {
        if (bridgeSink !== undefined) {
          bridgeSink(drained[i]);
        }
      }
    }, 500);
    // 自动保存检查（M4-01：防抖由 SaveScheduler 负责，轮询只触发到期保存）
    this.saveTimer = setInterval(() => {
      const c = this.coordinator;
      if (c === undefined) {
        return;
      }
      c.tick(Date.now()).then((ran: boolean) => {
        if (ran) {
          this.saveLabel = SaveStateMachine.label(c.state);
          this.conflictVisible = c.state === SaveState.CONFLICT;
          if (c.state === SaveState.ERROR) {
            this.append('[自动保存] 失败，保留未保存内容');
          }
        }
      });
    }, 500);
    this.resolveRouteParams();
  }

  aboutToDisappear(): void {
    if (this.flushTimer >= 0) {
      clearInterval(this.flushTimer);
      this.flushTimer = -1;
    }
    if (this.saveTimer >= 0) {
      clearInterval(this.saveTimer);
      this.saveTimer = -1;
    }
    bridgeSink = undefined;
  }

  /** 路由参数：name=内部相对路径 / uri=外部文档（M5-01 入口传递） */
  private resolveRouteParams(): void {
    const params = router.getParams();
    if (params === undefined || params === null) {
      return;
    }
    const pObj: ESObject = params as ESObject;
    const name = pObj.name as string | undefined;
    const uri = pObj.uri as string | undefined;
    if (name !== undefined && name.length > 0) {
      const src: InternalSource = { kind: 'internal', relativePath: name };
      this.docTarget = src;
      this.docTitle = name.substring(name.lastIndexOf('/') + 1);
      this.loadOpenedDoc(src);
    } else if (uri !== undefined && uri.length > 0) {
      const src: ExternalSource = { kind: 'external', uri: uri, displayName: uri };
      this.docTarget = src;
      this.docTitle = uri;
      this.loadOpenedDoc(src);
    }
  }

  /** 打开已有文档：读内容（Web 就绪后注入），基线 revision 用于冲突检测 */
  private loadOpenedDoc(target: DocumentSource): void {
    const src: DocumentFileAdapter = target.kind === 'internal' ? this.internal : this.external;
    src.read(target).then((r) => {
      this.expectedRevision = r.revision;
      this.pendingLoad = r.content;
      if (this.webReady) {
        this.flushPendingLoad();
      }
    }).catch((e: ESObject) => {
      this.append(`[打开] 失败：${JSON.stringify(e)}`);
    });
  }

  private flushPendingLoad(): void {
    const md = this.pendingLoad;
    this.pendingLoad = '';
    const js = `window.__editorApi.loadDocument(${JSON.stringify(md)});`;
    this.runJsValue(js).then(() => {
      this.docLength = md.length;
      this.append(`[打开] 文档 ${md.length} 字符`);
    });
  }

  /** 草稿检查点（FR-SAVE-003） */
  private doSaveCheckpoint(content: string): Promise<void> {
    const target = this.docTarget;
    if (target === undefined) {
      return Promise.resolve();
    }
    this.drafts.save(
      this.draftIdOf(target),
      this.fingerprintOf(target),
      this.expectedRevision.size,
      this.expectedRevision.contentHash,
      content,
    );
    return Promise.resolve();
  }

  /** 持久化：内部原子写 / 外部 URI 写；新建文档首次保存自动命名到资料库 */
  private async doPersist(content: string): Promise<WriteDocumentResult> {
    let target = this.docTarget;
    if (target === undefined) {
      const stamp = `${Date.now()}`;
      const src: InternalSource = { kind: 'internal', relativePath: `library/未命名-${stamp}.md` };
      target = src;
      this.docTarget = src;
      this.docTitle = `未命名-${stamp}.md`;
      this.append(`[保存] 新建文档 → 资料库/未命名-${stamp}.md`);
    }
    const result = target.kind === 'internal'
      ? await this.internal.write(target, content, this.expectedRevision)
      : await this.external.write(target, content, this.expectedRevision);
    if (result.ok) {
      this.expectedRevision = result.revision;
      this.drafts.remove(this.draftIdOf(target));
    }
    return result;
  }

  private draftIdOf(target: DocumentSource): string {
    if (target.kind === 'internal') {
      return `internal:${(target as InternalSource).relativePath}`;
    }
    return `external:${(target as ExternalSource).uri}`;
  }

  private fingerprintOf(target: DocumentSource): string {
    if (target.kind === 'internal') {
      return `internal:${(target as InternalSource).relativePath}`;
    }
    return `external:${(target as ExternalSource).uri}`;
  }

  /** 返回前未保存保护（M2-03）：草稿检查点已保留内容 */
  private goBack(): void {
    const c = this.coordinator;
    if (c !== undefined && (c.state === SaveState.DIRTY || c.state === SaveState.ERROR)) {
      AlertDialog.show({
        title: '未保存修改',
        message: '内容已由草稿检查点保留，是否在离开前保存？',
        primaryButton: {
          value: '保存并离开',
          action: () => {
            this.save().then(() => {
              router.back();
            });
          },
        },
        secondaryButton: {
          value: '放弃',
          action: () => {
            router.back();
          },
        },
        cancel: () => {
          // 取消：留在页面继续编辑
        },
      });
      return;
    }
    router.back();
  }

  /** 同步执行 JS 并返回结果（返回值通道，M0-03 实测可用） */
  private runJsValue(script: string): Promise<string> {
    return new Promise<string>((resolve) => {
      try {
        this.controller.runJavaScript(script, (err, result) => {
          resolve(err ? '' : (result === undefined ? '' : String(result)));
        });
      } catch (e) {
        resolve('');
      }
    });
  }

  /** 快捷栏命令：读取选区/全文 → 领域变换 → 写回 */
  private async applyCommand(cmd: MarkdownCommandName): Promise<void> {
    try {
      const selRaw = await this.runJsValue('window.__editorApi.getSelectionRange();');
      const text = await this.runJsValue('window.__editorApi.getSnapshot();');
      const parsed: ESObject = JSON.parse(selRaw);
      const range: TextRange = { from: parsed.from as number, to: parsed.to as number };
      const result: TextTransformResult = MarkdownCommands.apply(text, range, cmd);
      const payload: ESObject = {
        text: result.text,
        cursorFrom: result.selection.from,
        cursorTo: result.selection.to,
      } as ESObject;
      const js = `window.__editorApi.setDocument(${JSON.stringify(payload.text)}, ${payload.cursorFrom}, ${payload.cursorTo});`;
      await this.runJsValue(js);
      this.docLength = result.text.length;
      const c = this.coordinator;
      if (c !== undefined) {
        c.onEdit(Date.now());
        this.saveLabel = SaveStateMachine.label(c.state);
      }
    } catch (e) {
      this.append(`[命令] ${cmd} 失败：${JSON.stringify(e)}`);
    }
  }

  private async save(): Promise<void> {
    const c = this.coordinator;
    if (c === undefined) {
      return;
    }
    if (c.state === SaveState.CLEAN) {
      this.append('[保存] 无修改');
      return;
    }
    const ran = await c.saveNow(Date.now());
    this.saveLabel = SaveStateMachine.label(c.state);
    this.conflictVisible = c.state === SaveState.CONFLICT;
    this.append(`[保存] ${ran ? '完成' : '未执行'} → ${this.saveLabel}`);
  }

  /** M4-03 冲突决策①：改用磁盘版本（编辑器内容放弃；草稿检查点保留本地，磁盘已读回） */
  private conflictKeepDisk(): void {
    const c = this.coordinator;
    const target = this.docTarget;
    if (c === undefined || target === undefined) {
      return;
    }
    const src: DocumentFileAdapter = target.kind === 'internal' ? this.internal : this.external;
    src.read(target).then((r) => {
      this.expectedRevision = r.revision;
      this.pendingLoad = r.content;
      this.flushPendingLoad();
      c.decideKeepDisk();
      this.conflictVisible = false;
      this.saveLabel = SaveStateMachine.label(c.state);
      this.append('[冲突] 已加载磁盘版本');
    }).catch((e: ESObject) => {
      this.append(`[冲突] 读取磁盘版本失败：${JSON.stringify(e)}（保留本地编辑）`);
      c.decideKeepLocal();
      this.conflictVisible = false;
      this.saveLabel = SaveStateMachine.label(c.state);
    });
  }

  /** M4-03 冲突决策②：保留本地继续编辑（不再自动覆盖） */
  private conflictKeepLocal(): void {
    const c = this.coordinator;
    if (c === undefined) {
      return;
    }
    c.decideKeepLocal();
    this.conflictVisible = false;
    this.saveLabel = SaveStateMachine.label(c.state);
    this.append('[冲突] 保留本地内容继续编辑');
  }

  /** M4-03 冲突决策③：本地内容另存副本到资料库 */
  private async conflictSaveCopy(): Promise<void> {
    const c = this.coordinator;
    if (c === undefined) {
      return;
    }
    const stamp = `${Date.now()}`;
    const copy: InternalSource = { kind: 'internal', relativePath: `library/未命名-${stamp}.md` };
    this.docTarget = copy;
    c.decideKeepLocal();
    this.conflictVisible = false;
    const ran = await c.saveNow(Date.now());
    this.saveLabel = SaveStateMachine.label(c.state);
    this.append(`[冲突] 副本保存${ran && c.state !== SaveState.ERROR ? '完成' : '失败'} → ${copy.relativePath}`);
  }

  build() {
    Column({ space: 6 }) {
      // 标题栏
      Row({ space: 8 }) {
        Button('返回')
          .fontSize(13)
          .onClick(() => this.goBack())
        Text(this.docTitle)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .constraintSize({ maxWidth: 120 })
        Text(`保存：${this.saveLabel}`)
          .fontSize(13)
        Text(`长度：${this.docLength}`)
          .fontSize(13)
        Blank()
        Button('保存')
          .fontSize(13)
          .onClick(() => this.save())
      }
      .width('100%')

      // 快捷栏（FR-EDIT-002 命令子集）
      Row({ space: 6 }) {
        Button('加粗').fontSize(12).onClick(() => this.applyCommand('bold'))
        Button('斜体').fontSize(12).onClick(() => this.applyCommand('italic'))
        Button('删除线').fontSize(12).onClick(() => this.applyCommand('strike'))
        Button('行内码').fontSize(12).onClick(() => this.applyCommand('inlineCode'))
        Button('链接').fontSize(12).onClick(() => this.applyCommand('link'))
      }
      Row({ space: 6 }) {
        Button('·列表').fontSize(12).onClick(() => this.applyCommand('ul'))
        Button('1.列表').fontSize(12).onClick(() => this.applyCommand('ol'))
        Button('任务').fontSize(12).onClick(() => this.applyCommand('task'))
        Button('引用').fontSize(12).onClick(() => this.applyCommand('quote'))
        Button('代码块').fontSize(12).onClick(() => this.applyCommand('codeBlock'))
        Button('示例').fontSize(12).onClick(() => {
          const md = '# 正式编辑器\n\n**M2** 快捷栏命令测试：\n\n- 列表 A\n\n> 引用\n';
          const js = `window.__editorApi.setDocument(${JSON.stringify(md)}, 0, 0);`;
          this.runJsValue(js).then(() => {
            this.docLength = md.length;
            const c = this.coordinator;
            if (c !== undefined) {
              c.onEdit(Date.now());
              this.saveLabel = SaveStateMachine.label(c.state);
            }
          });
        })
      }
      .width('100%')

      // 冲突条（M4-03：外部修改检测后停止自动保存，等待用户决策）
      if (this.conflictVisible) {
        Row({ space: 8 }) {
          Text('⚠ 磁盘版本已变化（自动保存已停止）')
            .fontSize(12)
            .fontColor('#B00020')
          Button('用磁盘版')
            .fontSize(12)
            .onClick(() => this.conflictKeepDisk())
          Button('保留本地')
            .fontSize(12)
            .onClick(() => this.conflictKeepLocal())
          Button('另存副本')
            .fontSize(12)
            .onClick(() => this.conflictSaveCopy())
        }
        .width('100%')
        .padding(4)
        .backgroundColor('#FFF3E0')
      }

      Web({ src: $rawfile('web/editor.html'), controller: this.controller })
        .javaScriptAccess(true)
        .javaScriptProxy({
          object: { send: editorBridgeSend },
          name: '__nativeBridge',
          methodList: ['send'],
          controller: this.controller,
        })
        .onPageEnd(() => {
          this.webReady = true;
          if (this.pendingLoad.length > 0 || this.docTarget !== undefined) {
            this.flushPendingLoad();
          }
          this.append('编辑器就绪');
        })
        .onErrorReceive((event) => {
          this.append(`页面错误：${JSON.stringify(event.request)}`);
        })
        .layoutWeight(1)
        .width('100%')

      Text(this.log)
        .fontSize(11)
        .fontColor('#66000000')
        .maxLines(4)
        .width('100%')
    }
    .padding(8)
    .width('100%')
    .height('100%')
  }
}