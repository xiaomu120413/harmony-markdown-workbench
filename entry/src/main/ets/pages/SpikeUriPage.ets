import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-SPIKE';
const PREF_NAME: string = 'spike_uri_store';
const KEY_LAST_URI: string = 'last_uri';
const KEY_LAST_NAME: string = 'last_name';
const WRITE_PROBE: string = '\n<!-- hmwb-spike-write-probe: M0-02 原位保存测试标记，可安全删除 -->\n';

/**
 * M0-02 尖峰：外部文件 URI 访问验证页（无正式 UI，验证后由正式实现替换）。
 * 验证目标：
 *  1. DocumentViewPicker 选择 .md/.markdown/.txt
 *  2. URI 读取内容/元数据
 *  3. persistPermission 持久化授权（API 26 Beta 类型缺失，见 uri-permission-augment.d.ts 与 R-10）
 *  4. preferences 保存最近记录，重启后按 URI 再次访问
 *  5. 原位写入可行性（仅开启开关时执行，写入固定探针标记）
 */
@Entry
@Component
struct SpikeUriPage {
  @State log: string = '';
  @State currentUri: string = '';
  @State currentName: string = '';
  @State currentSize: string = '';
  @State persistState: string = '未尝试';
  @State reopenState: string = '未尝试';
  @State writeEnabled: boolean = false;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  private append(line: string): void {
    this.log = `${line}\n---\n${this.log}`;
    hilog.info(DOMAIN, TAG, '%{public}s', line);
  }

  private getNameFromUri(uri: string): string {
    const idx: number = uri.lastIndexOf('/');
    return idx >= 0 ? uri.substring(idx + 1) : uri;
  }

  private getPrefs(): Promise<preferences.Preferences> {
    return preferences.getPreferences(this.context, PREF_NAME);
  }

  private async selectAndRead(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker(this.context);
      const result: Array<string> = await documentPicker.select({ maxSelectNumber: 1 });
      if (result.length === 0) {
        this.append('未选择文件（用户取消）');
        return;
      }
      const uri: string = result[0];
      this.currentUri = uri;
      this.currentName = this.getNameFromUri(uri);

      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      this.currentSize = `${stat.size} 字节`;
      const text = fs.readTextSync(uri);
      fs.closeSync(file);
      this.append(`选择成功：${this.currentName}（${stat.size} 字节）`);
      this.append(`内容预览（前 200 字符）：\n${text.substring(0, 200).replace(/\n/g, '⏎')}`);
      this.persistState = '未尝试';
    } catch (e) {
      this.append(`选择/读取失败：${JSON.stringify(e)}`);
    }
  }

  private async diagPersistence(): Promise<void> {
    // API 26 Beta SDK（26.0.0.23）类型缺陷：@ohos.application.uriPermissionManager 的
    // namespace 为空（无成员声明），ArkTS 编译期无法调用 persistPermission（R-10）。
    // 本步改为诊断：通过"记录 URI → 杀进程重启 → 用记录重开"验证系统是否隐式持久化。
    this.persistState = '无法调用（SDK 类型缺失，R-10）';
    this.append('②持久化授权：API 26 Beta 类型缺失，编译期不可调用。');
    this.append('替代验证：请执行 ③记入最近 → 杀进程并重启应用 → ④用记录重开。');
    this.append('若重开失败，说明 URI 授权仅在单次运行内有效，V0.1 需走"临时访问 + 重新定位"降级路径（SDD M0-02 门禁）。');
  }

  private async saveRecent(): Promise<void> {
    if (this.currentUri.length === 0) {
      this.append('请先选择文件');
      return;
    }
    try {
      const prefs = await this.getPrefs();
      await prefs.put(KEY_LAST_URI, this.currentUri);
      await prefs.put(KEY_LAST_NAME, this.currentName);
      await prefs.flush();
      this.append(`最近记录已保存：${this.currentName}`);
    } catch (e) {
      this.append(`保存最近记录失败：${JSON.stringify(e)}`);
    }
  }

  private async reopenFromRecord(): Promise<void> {
    // 模拟"重启后再次访问"：从持久存储取 URI 并尝试打开。
    // 重启应用后此按钮仍可点，若持久授权有效则能读取。
    try {
      const prefs = await this.getPrefs();
      const uri = (await prefs.get(KEY_LAST_URI, '')) as string;
      const name = (await prefs.get(KEY_LAST_NAME, '')) as string;
      if (uri.length === 0) {
        this.append('没有最近记录，请先执行第③步');
        this.reopenState = '无记录';
        return;
      }
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const size = fs.statSync(file.fd).size;
      fs.closeSync(file);
      this.reopenState = `重新打开成功：${name}（${size} 字节）`;
      this.append(this.reopenState);
    } catch (e) {
      this.reopenState = '重新打开失败（权限失效或文件被移动/删除）';
      this.append(`${this.reopenState}：${JSON.stringify(e)}`);
    }
  }

  private async probeInPlaceWrite(): Promise<void> {
    if (this.currentUri.length === 0) {
      this.append('请先选择文件');
      return;
    }
    if (!this.writeEnabled) {
      this.append('写测试开关未开启，已跳过（避免意外修改文件）');
      return;
    }
    try {
      const file = fs.openSync(this.currentUri, fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND);
      fs.writeSync(file.fd, WRITE_PROBE);
      fs.closeSync(file);
      this.append('原位写入成功（已追加探针标记，可手动删除）');
    } catch (e) {
      this.append(`原位写入失败（只读 URI/权限不足）：${JSON.stringify(e)}`);
    }
  }

  aboutToAppear(): void {
    this.append('M0-02 尖峰页就绪。');
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Button('返回首页')
          .fontSize(14)
          .onClick(() => router.back())
        Blank()
      }
      .width('100%')

      Text('M0-02 外部文件 URI 尖峰')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      Text(`当前：${this.currentName || '（无）'}\n${this.currentUri || ''}\n${this.currentSize}`)
        .fontSize(12)
        .fontColor('#66000000')
        .maxLines(3)

      Row({ space: 8 }) {
        Button('① 选择并读取')
          .fontSize(13)
          .onClick(() => this.selectAndRead())
        Button('② 持久化诊断')
          .fontSize(13)
          .onClick(() => this.diagPersistence())
      }
      Row({ space: 8 }) {
        Button('③ 记入最近')
          .fontSize(13)
          .onClick(() => this.saveRecent())
        Button('④ 用记录重开')
          .fontSize(13)
          .onClick(() => this.reopenFromRecord())
      }
      Row() {
        Text('⑤ 原位写测试：')
          .fontSize(13)
        Toggle({ type: ToggleType.Switch, isOn: this.writeEnabled })
          .onChange((v: boolean) => {
            this.writeEnabled = v;
          })
        Button('执行写入')
          .fontSize(13)
          .onClick(() => this.probeInPlaceWrite())
      }
      .width('100%')

      Text(`持久化：${this.persistState}   复开：${this.reopenState}`)
        .fontSize(12)
        .fontColor('#99000000')

      Scroll() {
        Text(this.log)
          .fontSize(12)
          .textAlign(TextAlign.Start)
          .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
    }
    .padding(12)
    .width('100%')
    .height('100%')
  }
}