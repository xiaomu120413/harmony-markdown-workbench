import { router } from '@kit.ArkUI';
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
    if (this.host.isActive() && action !== undefined) { action(); }
  }

  saveStatusColor(): string {
    return this.host.state.saveLabel === '已保存' ? this.host.state.pal.TEXT_SUB
      : this.host.state.saveLabel === '外部冲突' || this.host.state.saveLabel === '保存失败' ? this.host.state.pal.DANGER : this.host.state.pal.AMBER;
  }

  async showLocation(): Promise<void> {
    const source = this.host.state.docTarget;
    const persistent = source?.kind === 'external' ? await this.host.env.external.canPersistAccess(source) : false;
    if (!this.host.isActive() || source !== this.host.state.docTarget) { return; }
    AlertDialog.show({ title: '当前保存位置', message: source === undefined
      ? '尚未保存到文件；恢复草稿仅在本机应用内保留。'
      : source.kind === 'internal'
        ? `我的文档 / ${source.relativePath.substring('library/'.length)}\n应用私有目录，卸载前请导出文档和附件。`
        : `外部原文件\n${source.uri}\n${persistent ? '已保留此文件的访问授权；移动文件或撤销授权后需重新选择。' : '临时访问授权；重启后可能需要重新选择文件。'}`,
      confirm: { value: '知道了', action: () => {} } });
  }

  showSettings(): void {
    router.pushUrl({ url: 'pages/SettingsPage' });
  }
}
