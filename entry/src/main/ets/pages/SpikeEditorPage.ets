import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, router } from '@kit.ArkUI';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-SPIKE-EDITOR';

// 模块级桥接回调（ArkWeb javaScriptProxy 要求普通函数，不能捕获组件 this）
let bridgeHandler: ((type: string, payload: string) => void) | undefined = undefined;

function nativeBridgeSend(type: string, payload: string): void {
  if (bridgeHandler !== undefined) {
    bridgeHandler(type, payload);
  }
}

const SAMPLE_MD: string = `# 尖峰测试文档

这是一个 **M0-03** 尖峰页面，用于验证 ArkWeb + CodeMirror 6：

- 中文输入测试：你好，鸿蒙！拼音连续输入
- 列表续行测试
- 撤销重做测试

| 列1 | 列2 |
|---|---|
| a | b |

\`\`\`ts
function test(): number {
  return 42;
}
\`\`\`

> 引用块：Markdown 编辑器工作台
`;

/**
 * M0-03 尖峰：ArkWeb 编辑运行时验证页（无正式 UI，验证后由 M2 正式实现替换）。
 * 验证：本地 rawfile 加载、CodeMirror 6 编辑、JSBridge 最小协议、
 * 中文输入、快照获取、主题切换。
 */
@Entry
@Component
struct SpikeEditorPage {
  @State log: string = '';
  @State themeDark: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private sampleLoaded: boolean = false;

  private static escapeJs(s: string): string {
    return s.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\r?\n/g, '\\n');
  }

  private append(line: string): void {
    this.log = `${line}\n---\n${this.log}`;
    hilog.info(DOMAIN, TAG, '%{public}s', line);
  }

  aboutToAppear(): void {
    bridgeHandler = (type: string, payload: string): void => {
      this.onBridgeMessage(type, payload);
    };
  }

  aboutToDisappear(): void {
    bridgeHandler = undefined;
  }

  private runJs(script: string): void {
    try {
      this.controller.runJavaScript(script, (err, result) => {
        if (err) {
          this.append(`runJavaScript 失败: ${JSON.stringify(err)}`);
          return;
        }
        if (result !== undefined && result !== '') {
          this.append(`JS 返回: ${String(result).substring(0, 200)}`);
        }
      });
    } catch (e) {
      this.append(`runJavaScript 异常: ${JSON.stringify(e)}`);
    }
  }

  private onBridgeMessage(type: string, payload: string): void {
    // Web → 原生事件（M2-02 将协议版本化）
    // runJavaScript 直接返回值在本环境不可靠（返回 null），
    // 快照/诊断采用 Web 主动推送（SDD 8.4 请求式快照）。
    if (type === 'snapshot') {
      const text: string = JSON.parse(payload).text;
      this.append(`[snapshot] 长度=${text.length}\n${text.substring(0, 150).replace(/\n/g, '⏎')}`);
      return;
    }
    if (type === 'diag') {
      this.append(`[diag] ${payload}`);
      return;
    }
    this.append(`[web→native] ${type}: ${payload.substring(0, 120)}`);
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Button('返回')
          .fontSize(14)
          .onClick(() => router.back())
        Blank()
        Button('示例')
          .fontSize(13)
          .onClick(() => {
            this.sampleLoaded = true;
            const js = `window.__editorApi.loadDocument('${SpikeEditorPage.escapeJs(SAMPLE_MD)}');`;
            this.runJs(js);
            this.append('已加载示例 Markdown');
          })
        Button('快照')
          .fontSize(13)
          .onClick(() => {
            // 返回值通道实测可用（空字符串会以 null 返回，先加载内容再快照）
            this.runJs('window.__editorApi.getSnapshot();');
          })
        Button('深色')
          .fontSize(13)
          .onClick(() => {
            this.themeDark = !this.themeDark;
            this.runJs(`window.__editorApi.setTheme(${this.themeDark});`);
            this.append(`主题切换: ${this.themeDark ? 'dark' : 'light'}`);
          })
        Button('返回测')
          .fontSize(13)
          .onClick(() => {
            this.runJs('"hello-return"');
          })
        Button('诊断')
          .fontSize(13)
          .onClick(() => {
            // M0-03 诊断：验证 CodeMirror 状态与文档长度（返回值方式）
            this.runJs("(function(){var e=document.getElementById('js-err');var v=window.__editorApi;return 'err='+(e?e.textContent:'none')+';api='+(v?'ok':'miss');})();");
          })
      }
      .width('100%')

      Web({ src: $rawfile('web/editor.html'), controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .javaScriptProxy({
          object: {
            send: nativeBridgeSend,
          },
          name: '__nativeBridge',
          methodList: ['send'],
          controller: this.controller,
        })
        .onPageEnd(() => {
          this.append('页面加载完成（editor.html ready）');
        })
        .onConsole((event) => {
          const msg: string = event.message.getMessage();
          if (msg.includes('HMWB_BRIDGE')) {
            this.append(`[console] ${msg.substring(0, 120)}`);
          }
          return false;
        })
        .onTitleReceive((event) => {
          const title: string = event.title;
          if (title.startsWith('CM:')) {
            this.append(`[title] ${title.substring(0, 160)}`);
          }
        })
        .onErrorReceive((event) => {
          this.append(`页面加载错误: ${JSON.stringify(event.request)}`);
        })
        .layoutWeight(1)
        .width('100%')

      Text(this.log)
        .fontSize(11)
        .fontColor('#66000000')
        .maxLines(6)
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .padding(8)
    .width('100%')
    .height('100%')
  }
}