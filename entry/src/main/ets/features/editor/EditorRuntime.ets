import { webview } from '@kit.ArkWeb';
import { MarkdownCommands, MarkdownCommandName, TextRange, TextTransformResult } from '../../domain/editor/MarkdownCommands';
import { RecentFileList } from '../../domain/document/RecentFileList';
import { EditorController } from './EditorController';
export class EditorRuntime {
  private host: EditorController;
  constructor(host: EditorController) { this.host = host; }
  runJsChecked(ctrl: webview.WebviewController, script: string): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('编辑器响应超时')), 5000);
      try {
        ctrl.runJavaScript(script, (err, result) => {
          clearTimeout(timer);
          if (err || result === undefined) { reject(new Error('编辑器读取失败')); }
          else { resolve(this.host.decodeReturn(result)); }
        });
      } catch (e) { clearTimeout(timer); reject(new Error('编辑器暂不可用')); }
    });
  }

  runJsValue(script: string): Promise<string> {
    return this.host.runJsValueOn(this.host.env.controller, script);
  }

  runJsValueOn(ctrl: webview.WebviewController, script: string): Promise<string> {
    return new Promise<string>((resolve) => {
      try {
        ctrl.runJavaScript(script, (err, result) => {
          resolve(err ? '' : (result === undefined ? '' : this.host.decodeReturn(result)));
        });
      } catch (e) {
        resolve('');
      }
    });
  }

  decodeReturn(result: string): string {
    const trimmed = result.trim();
    if (trimmed.length === 0 || trimmed.charAt(0) !== '"') {
      return result;
    }
    try {
      const v: ESObject = JSON.parse(trimmed);
      return v as string;
    } catch (e) {
      return result;
    }
  }

  async applyCommand(cmd: MarkdownCommandName): Promise<void> {
    if (this.host.state.deliveryBusy) { return; }
    try {
      const selRaw = await this.host.runJsValue('window.__editorApi.getSelectionRange();');
      const text = await this.host.runJsValue('window.__editorApi.getSnapshot();');
      const parsed: ESObject = JSON.parse(selRaw);
      const range: TextRange = { from: parsed.from as number, to: parsed.to as number };
      const result: TextTransformResult = MarkdownCommands.apply(text, range, cmd);
      const payload: ESObject = {
        text: result.text,
        cursorFrom: result.selection.from,
        cursorTo: result.selection.to,
      } as ESObject;
      const js = `window.__editorApi.setDocument(${JSON.stringify(payload.text)}, ${payload.cursorFrom}, ${payload.cursorTo});`;
      await this.host.runJsValue(js);
      this.host.state.docLength = result.text.length;
      this.host.markEdited();
    } catch (e) {
      this.host.append(`[命令] ${cmd} 失败：${JSON.stringify(e)}`);
    }
  }

  async applyHistory(kind: 'undo' | 'redo'): Promise<void> {
    if (this.host.state.deliveryBusy) { return; }
    const len = await this.host.runJsValue(`window.__editorApi.${kind}();`);
    if (len.length > 0) {
      const n = Number(len);
      if (!Number.isNaN(n)) {
        this.host.state.docLength = n;
      }
    }
  }

  documentLocation(): string {
    const target = this.host.state.docTarget;
    return target === undefined ? '尚未保存到文件' : target.kind === 'internal'
      ? '我的文档 · 应用内' : RecentFileList.location(target.uri);
  }

  dismissFileSheet(action: () => void): void {
    this.host.env.afterFileSheet = action;
    this.host.state.fileSheetVisible = false;
  }

  fileSheetClosed(): void {
    this.host.state.fileSheetVisible = false;
    const action = this.host.env.afterFileSheet;
    this.host.env.afterFileSheet = undefined;
    if (this.host.state.pageActive && action !== undefined) { action(); }
  }

  saveStatusColor(): string {
    return this.host.state.saveLabel === '已保存' ? this.host.state.pal.TEXT_SUB
      : this.host.state.saveLabel === '外部冲突' || this.host.state.saveLabel === '保存失败' ? this.host.state.pal.DANGER : this.host.state.pal.AMBER;
  }

  showLocation(): void {
    const source = this.host.state.docTarget;
    AlertDialog.show({ title: '当前保存位置', message: source === undefined
      ? '尚未保存到文件；恢复草稿仅在本机应用内保留。'
      : source.kind === 'internal'
        ? `我的文档 / ${source.relativePath.substring('library/'.length)}\n应用私有目录，卸载前请导出文档和附件。`
        : `外部原文件（临时访问授权）\n${source.uri}\n重启后可能需要重新选择文件。`,
      confirm: { value: '知道了', action: () => {} } });
  }

  showHelp(): void {
    AlertDialog.show({
      title: '木笺 MuMark · 快捷键与提示',
      message: [
        '快捷键：',
        '· Ctrl+S 保存　Ctrl+F 查找　Ctrl+Shift+F 大纲',
        '· Ctrl+B 加粗　Ctrl+I 斜体',
        '· Ctrl+Z 撤销　Ctrl+Y 重做',
        '',
        '工具栏：',
        '· H1–H6 标题（同级再点取消，异级切换）',
        '· B/I/S/高亮/行内码 行内样式',
        '· 列表/序号/任务/引用/代码块/缩进 块级',
        '· 链接/图片/表格/分隔线 插入',
        '',
        '视图：',
        '· 编辑/预览/分屏 顶栏切换（平板与电脑支持分屏）',
        '· 文档侧栏　大纲面板点击标题跳转',
        '',
        '保存：',
        '· 修改自动保存（1.5 秒防抖）',
        '· 文档菜单：另存为、导出副本、图文 ZIP、HTML、复制',
        '· 意外退出可在首页「找回未保存内容」恢复',
      ].join('\n'),
      confirm: {
        value: '知道了',
        action: () => {
        },
      },
    });
  }
}
