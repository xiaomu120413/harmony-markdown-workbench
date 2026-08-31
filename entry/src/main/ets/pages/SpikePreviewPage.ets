import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';
import { HeadingOutline } from '../domain/editor/HeadingOutline';
import { FindReplaceEngine, FindOptions } from '../domain/editor/FindReplaceEngine';
import { HtmlSafety } from '../domain/preview/HtmlSafety';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-SPIKE-PREVIEW';

const SAMPLE_MD: string = [
  '# 文档标题',
  '',
  '## 章节一',
  '',
  '表格：',
  '',
  '| 姓名 | 分数 |',
  '| --- | --- |',
  '| 张三 | 90 |',
  '',
  '- [x] 已完成任务',
  '- [ ] 待办任务',
  '',
  '~~删除线文本~~ 与 **加粗** 和 `行内码`。',
  '',
  '```ts',
  'const x = 1;',
  '```',
  '',
  '## 章节一（重名）',
].join('\n');

const MALICIOUS_MD: string = [
  '# 安全测试',
  '',
  '<script>window.__hacked = true;</script>',
  '',
  '<img src="x" onerror="window.__hacked2 = true">',
  '',
  '[点我](javascript:alert(1))',
  '',
  '<iframe src="https://evil.example"></iframe>',
].join('\n');

/**
 * M3 尖峰：预览渲染与安全验证页（FR-PREVIEW-001/002/003 + FR-EDIT-004 领域挂接）。
 */
@Entry
@Component
struct SpikePreviewPage {
  @State log: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();

  private append(line: string): void {
    this.log = `${line}\n---\n${this.log}`;
    hilog.info(DOMAIN, TAG, '%{public}s', line);
  }

  private renderMd(text: string): void {
    this.controller.runJavaScript(
      `window.__previewApi.render(${JSON.stringify(text)});`,
      (err, result) => {
        if (err) {
          this.append(`渲染失败：${JSON.stringify(err)}`);
          return;
        }
        this.append(`渲染完成（${String(result).substring(0, 60)}）`);
      });
  }

  /** ① 渲染 GFM 示例 */
  renderSample(): void {
    this.renderMd(SAMPLE_MD);
  }

  /** ② 渲染恶意语料 + 领域安全检测 */
  async renderMalicious(): Promise<void> {
    this.renderMd(MALICIOUS_MD);
    const r = HtmlSafety.inspect(MALICIOUS_MD);
    this.append(`[安全检测] safe=${r.safe} 问题=${r.issues.length}`);
    for (let i = 0; i < r.issues.length; i++) {
      this.append(`  - ${r.issues[i].kind}: ${r.issues[i].detail}`);
    }
  }

  /** ③ 大纲提取（领域层） */
  extractOutline(): void {
    const items = HeadingOutline.extract(SAMPLE_MD);
    let out = '';
    for (let i = 0; i < items.length; i++) {
      out += `${'  '.repeat(items[i].level - 1)}${items[i].text} (#${items[i].id} L${items[i].line})\n`;
    }
    this.append(`[大纲] ${items.length} 项\n${out.trimEnd()}`);
  }

  /** ④ 查找计数（领域层） */
  find(): void {
    const opts: FindOptions = { caseSensitive: false, wholeWord: false };
    const matches = FindReplaceEngine.findAll(SAMPLE_MD, '章节', opts);
    this.append(`[查找] "章节" 命中 ${matches.length} 次（大小写不敏感）`);
    const ww: FindOptions = { caseSensitive: true, wholeWord: true };
    const m2 = FindReplaceEngine.findAll(SAMPLE_MD, '张三', ww);
    this.append(`[查找] "张三"（全词）命中 ${m2.length} 次`);
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Button('返回')
          .fontSize(13)
          .onClick(() => router.back())
        Button('① 渲染示例')
          .fontSize(13)
          .onClick(() => this.renderSample())
        Button('② 恶意语料')
          .fontSize(13)
          .onClick(() => this.renderMalicious())
        Button('③ 大纲')
          .fontSize(13)
          .onClick(() => this.extractOutline())
        Button('④ 查找')
          .fontSize(13)
          .onClick(() => this.find())
      }
      .width('100%')

      Row() {
        Text('预览（Web 渲染）')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
        Blank()
      }
      .width('100%')

      Web({ src: $rawfile('web/preview.html'), controller: this.controller })
        .javaScriptAccess(true)
        .onPageEnd(() => {
          this.append('预览运行时就绪');
        })
        .layoutWeight(1)
        .width('100%')

      Text(this.log)
        .fontSize(11)
        .fontColor('#66000000')
        .maxLines(5)
        .width('100%')
    }
    .padding(8)
    .width('100%')
    .height('100%')
  }
}