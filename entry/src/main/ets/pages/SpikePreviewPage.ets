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
    const t0 = Date.now();
    this.controller.runJavaScript(
      `window.__previewApi.render(${JSON.stringify(text)});`,
      (err, result) => {
        const dt = Date.now() - t0;
        if (err) {
          this.append(`渲染失败（${dt}ms）：${JSON.stringify(err)}`);
          return;
        }
        this.append(`渲染完成（${dt}ms，${String(result).substring(0, 60)}）`);
      });
  }

  /** M6-02 样本构造：S2 = 1MB（500 标题 + 100 代码块）；S4 = 100 张本地图片引用 */
  private static buildS2(): string {
    let big = '';
    for (let i = 0; i < 500; i++) {
      big += `## 标题 ${i}\n\n段落 ${i} 的正文内容，包含 **加粗** 与 \`行内码\`。\n\n`;
    }
    for (let i = 0; i < 100; i++) {
      big += `\`\`\`ts\nconst v${i} = ${i};\n\`\`\`\n\n`;
    }
    return big;
  }

  private static buildS4(): string {
    let md = '# 图片文档\n\n';
    for (let i = 0; i < 100; i++) {
      md += `![图片 ${i}](file:///data/local/tmp/img-${i}.png)\n\n`;
    }
    return md;
  }

  /** ⑤ S2 样本渲染（1MB：首次预览性能基线） */
  renderS2(): void {
    this.renderMd(SpikePreviewPage.buildS2());
  }

  /** ⑥ S4 样本渲染（100 本地图引用：不崩溃） */
  renderS4(): void {
    this.renderMd(SpikePreviewPage.buildS4());
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
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
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
        Button('⑤ S2 渲染')
          .fontSize(13)
          .onClick(() => this.renderS2())
        Button('⑥ S4 渲染')
          .fontSize(13)
          .onClick(() => this.renderS4())
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