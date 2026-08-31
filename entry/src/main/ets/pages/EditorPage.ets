import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';
import { SaveStateMachine, SaveState } from '../domain/recovery/SaveStateMachine';
import { MarkdownCommands, MarkdownCommandName, TextRange, TextTransformResult } from '../domain/editor/MarkdownCommands';
import { EditorBridge } from '../services/EditorBridge';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-EDITOR';

/** 桥消息队列（ArkWeb jsProxy 回调线程不能操作组件 this——M0-03 R-16 结论） */
let pendingBridge: Array<string> = [];
let bridgeSink: ((msg: string) => void) | undefined = undefined;

function editorBridgeSend(raw: string): void {
  pendingBridge.push(raw);
}

/**
 * M2 正式编辑器页（基于 M0-03 验证的 CM6.x 运行时与桥模式）。
 * 组件：编辑器 + Markdown 快捷栏（领域命令变换）+ 保存状态。
 */
@Entry
@Component
struct EditorPage {
  @State log: string = '';
  @State saveLabel: string = '已保存';
  @State docLength: number = 0;
  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: EditorBridge = new EditorBridge();
  private sm: SaveStateMachine = new SaveStateMachine();
  private flushTimer: number = -1;

  private append(line: string): void {
    this.log = `${line}\n---\n${this.log}`;
    hilog.info(DOMAIN, TAG, '%{public}s', line);
  }

  aboutToAppear(): void {
    bridgeSink = (raw: string): void => {
      const env = this.bridge.parseEvent(raw);
      if (env !== undefined && this.bridge.isFirstResponse(env.id)) {
        this.append(`[event] ${env.type}`);
      }
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
  }

  aboutToDisappear(): void {
    if (this.flushTimer >= 0) {
      clearInterval(this.flushTimer);
      this.flushTimer = -1;
    }
    bridgeSink = undefined;
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
      const charsRaw = await this.runJsValue('window.__editorApi.getCharsAround();');
      void charsRaw;
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
      this.markDirty();
    } catch (e) {
      this.append(`[命令] ${cmd} 失败：${JSON.stringify(e)}`);
    }
  }

  private markDirty(): void {
    if (this.sm.state === SaveState.CLEAN) {
      this.sm.edit();
    }
    this.saveLabel = SaveStateMachine.label(this.sm.state);
  }

  private async save(): Promise<void> {
    if (this.sm.state === SaveState.CLEAN) {
      this.append('[保存] 无修改');
      return;
    }
    this.sm.beginSave();
    this.saveLabel = SaveStateMachine.label(this.sm.state);
    const text = await this.runJsValue('window.__editorApi.getSnapshot();');
    void text; // M2 骨架：保存对接 SaveCoordinator 在 M4-01
    setTimeout(() => {
      this.sm.saveSuccess();
      this.saveLabel = SaveStateMachine.label(this.sm.state);
      this.append('[保存] 完成（M4-01 将接入 SaveCoordinator 持久化）');
    }, 300);
  }

  build() {
    Column({ space: 6 }) {
      // 标题栏
      Row({ space: 8 }) {
        Button('返回')
          .fontSize(13)
          .onClick(() => router.back())
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
            this.markDirty();
          });
        })
      }
      .width('100%')

      Web({ src: $rawfile('web/editor.html'), controller: this.controller })
        .javaScriptAccess(true)
        .javaScriptProxy({
          object: { send: editorBridgeSend },
          name: '__nativeBridge',
          methodList: ['send'],
          controller: this.controller,
        })
        .onPageEnd(() => {
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