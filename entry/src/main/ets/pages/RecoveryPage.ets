import { SafePage } from '../components/SafePage';
import { ControlStyle, ControlMetrics } from '../common/ControlStyle';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, promptAction } from '@kit.ArkUI';
import { DraftStore } from '../infrastructure/metadata/DraftStore';
import { MetadataStore } from '../infrastructure/metadata/MetadataStore';
import { RecentFileList } from '../domain/document/RecentFileList';
import { InternalFileSource } from '../infrastructure/file/InternalFileSource';
import { DraftDecisionEvaluator, RecoveryDecision, RecoveryDraft } from '../domain/recovery/DraftDecision';
import { FileRevisionContract, InternalSource, WriteFailResult } from '../domain/document/DocumentFileAdapter';
import { FileRevision } from '../domain/document/FileRevision';
import { HashUtil } from '../domain/document/HashUtil';
import { DocumentNamer } from '../domain/document/DocumentNamer';
import { SettingsStore } from '../infrastructure/metadata/SettingsStore';
import { ThemeMode } from '../domain/settings/AppSettings';
import { AppTheme } from '../common/AppTheme';
import { beginWindowMove } from '../common/WindowDrag';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-RECOVERY';

/** 展示行：草稿 + 决策 */
interface DraftRow {
  draft: RecoveryDraft;
  decisionName: string;
  decision: RecoveryDecision;
  diskChanged: boolean;
}

/**
 * M4-04 崩溃恢复页（FR-SAVE-004 / SDD 9.3）。
 * 启动入口：HomePage「找回未保存内容 (N)」。
 * 规则（领域决策器）：
 *  - 草稿比磁盘新且磁盘未变 → 恢复（写回，不覆盖其他内容）；
 *  - 磁盘已变（外部修改）→ 冲突：不自动覆盖，只允许另存副本/保留草稿；
 *  - 内容已落盘 → 冗余可清理；
 *  - 损坏草稿自动跳过（隔离在上层，可整目录删除）。
 */
@Entry
@Component
struct RecoveryPage {
  @StorageProp('titleControlsBottom') captionBottom: number = 0;
  @State rows: Array<DraftRow> = [];
  @State pal: AppTheme = AppTheme.light();
  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private store: DraftStore = new DraftStore(getContext(this) as common.UIAbilityContext);
  private internal: InternalFileSource = new InternalFileSource(getContext(this) as common.UIAbilityContext);
  private meta: MetadataStore = new MetadataStore(getContext(this) as common.UIAbilityContext);

  /** M5-01：恢复写回/另存副本后同步最近列表元数据（失败不阻塞正文） */
  private async trackRecent(relativePath: string): Promise<void> {
    try {
      const entries = await this.meta.loadRecent();
      const list = new RecentFileList(entries);
      list.touch(relativePath, Date.now());
      await this.meta.saveRecent(list.snapshot());
    } catch (e) {
      // 元数据失败不影响正文
    }
  }

  private note(line: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', line);
  }

  async aboutToAppear(): Promise<void> {
    try {
      const st = await new SettingsStore(this.ctx).load();
      this.pal = AppTheme.of(st.theme === ThemeMode.DARK);
    } catch (e) {
      // 主题读取失败按浅色
    }
    await this.reload();
  }

  private async reload(): Promise<void> {
    const all = this.store.listAll();
    const out: Array<DraftRow> = [];
    for (let i = 0; i < all.length; i++) {
      const d = all[i];
      const diskRev = await this.diskRevisionOf(d.sourceFingerprint);
      const decision = DraftDecisionEvaluator.decide(d, diskRev, HashUtil.of(d.content));
      let name: string;
      switch (decision) {
        case RecoveryDecision.NO_DRAFT:
        case RecoveryDecision.DISCARD_REDUNDANT:
          name = '冗余可清理';
          break;
        case RecoveryDecision.RESTORE_DRAFT:
          name = '可恢复';
          break;
        default:
          name = '冲突（勿自动覆盖）';
          break;
      }
      out.push({ draft: d, decisionName: name, decision: decision, diskChanged: diskRev !== undefined && (diskRev as FileRevision).contentHash !== d.baseRevision.contentHash });
    }
    this.rows = out;
    this.note(`[恢复] ${out.length} 个检查点`);
  }

  /** 磁盘 revision：internal 可 stat；external（临时授权可能已失效）→ undefined */
  private async diskRevisionOf(fingerprint: string): Promise<FileRevision | undefined> {
    if (!fingerprint.startsWith('internal:')) {
      return undefined;
    }
    const rel = fingerprint.substring('internal:'.length);
    try {
      const src: InternalSource = { kind: 'internal', relativePath: rel };
      const c = await this.internal.stat(src);
      const rev: FileRevision = { size: c.size, contentHash: c.contentHash, modifiedTime: c.modifiedTime };
      return rev;
    } catch (e) {
      return undefined;
    }
  }

  private fmtTime(ms: number): string {
    const d = new Date(ms);
    const hour = `${d.getHours()}`.padStart(2, '0');
    const minute = `${d.getMinutes()}`.padStart(2, '0');
    return `${d.getMonth() + 1}/${d.getDate()} ${hour}:${minute}`;
  }

  /** 恢复：草稿内容写回源文档（磁盘==基线才写，写前复核决策） */
  private async restoreRow(row: DraftRow): Promise<void> {
    if (row.decision !== RecoveryDecision.RESTORE_DRAFT) {
      this.note(`[恢复] 决策为 ${row.decisionName}，跳过自动覆盖`);
      promptAction.showToast({ message: '磁盘已有变化，请使用「另存副本」' });
      return;
    }
    const d = row.draft;
    if (!d.sourceFingerprint.startsWith('internal:')) {
      // A3：会话草稿（session:new）与外部草稿均无原位写回目标 → 另存副本
      this.note('[恢复] 仅内部文档支持自动写回；外部/会话草稿请用另存副本');
      promptAction.showToast({ message: '请使用「另存副本」保存到资料库' });
      return;
    }
    const rel = d.sourceFingerprint.substring('internal:'.length);
    const src: InternalSource = { kind: 'internal', relativePath: rel };
    try {
      const base: FileRevisionContract = {
        size: d.baseRevision.size,
        contentHash: d.baseRevision.contentHash,
        modifiedTime: d.baseRevision.modifiedTime,
      };
      const result = await this.internal.write(src, d.content, base);
      if (result.ok) {
        this.store.remove(d.documentId);
        this.trackRecent(rel);
        this.note(`[恢复] 已写回 ${rel} 并清除草稿`);
      } else {
        this.note(`[恢复] 写回冲突/失败：${(result as WriteFailResult).message}（请改用另存副本）`);
        promptAction.showToast({ message: '写回失败，请使用「另存副本」' });
      }
    } catch (e) {
      this.note(`[恢复] 写回异常：${JSON.stringify(e)}`);
    }
    await this.reload();
  }

  /** 另存副本：草稿 → 资料库新文档，随后清除草稿（内容已有可靠副本） */
  private async saveCopy(row: DraftRow): Promise<void> {
    const d = row.draft;
    const name = DocumentNamer.derive(d.content, this.internal.listLibrary());
    const rel = `library/${name}`;
    const src: InternalSource = { kind: 'internal', relativePath: rel };
    try {
      const result = await this.internal.write(src, d.content, { size: 0, contentHash: '' });
      if (result.ok) {
        this.store.remove(d.documentId);
        this.trackRecent(rel);
        this.note(`[副本] 已保存 ${rel} 并清除草稿`);
      } else {
        this.note(`[副本] 失败：${(result as WriteFailResult).message}`);
        promptAction.showToast({ message: '另存副本失败' });
      }
    } catch (e) {
      this.note(`[副本] 异常：${JSON.stringify(e)}`);
    }
    await this.reload();
  }

  /** 清理冗余/放弃草稿（操作有明确两次意图：行内按钮文本即确认） */
  private discardRow(row: DraftRow): void {
    this.store.remove(row.draft.documentId);
    this.note(`[清理] 已删除草稿 ${row.draft.documentId}`);
    this.reload();
  }

  @Builder
  pageContent() {
    // 外层全宽容器负责水平居中（页面根上的 alignSelf 不生效）
    Column() {
    Stack({ alignContent: Alignment.Top }) {
      Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20).fontColor([this.pal.TEXT])
        }
          .attributeModifier(new ControlStyle(this.pal, 'quiet', true)).accessibilityText('返回')
          .onClick(() => router.back())
        Text('找回未保存内容')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.TEXT)
          .padding({ top: 6, bottom: 6 })
          .onTouch((e: TouchEvent) => {
            // 系统标题栏已隐藏：标题区接管窗口拖动
            if (e.type === TouchType.Down) {
              beginWindowMove(this.ctx);
            }
          })
        Blank()
      }
      .width('100%')

      if (this.rows.length === 0) {
        Text('没有需要恢复的内容。\n应用意外退出时，未保存的内容会自动保留在这里。')
          .fontSize(13)
          .fontColor(this.pal.TEXT_SUB)
          .width('100%')
      }

      List({ space: 8 }) {
        ForEach(this.rows, (row: DraftRow) => {
          ListItem() {
            Column({ space: 4 }) {
              Row({ space: 8 }) {
                Text(row.draft.sourceFingerprint === 'session:new' ? '未保存的新文档' : RecentFileList.displayName(row.draft.sourceFingerprint.replace('internal:library/', 'library/')))
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.pal.TEXT)
                  .layoutWeight(1)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.fmtTime(row.draft.updatedAt))
                  .fontSize(12)
                  .fontColor(this.pal.TEXT_SUB)
                  .constraintSize({ minWidth: 110 }).maxLines(1)
              }
              .width('100%')

              Text(row.decisionName)
                .fontSize(11)
                .fontColor(row.decision === RecoveryDecision.CONFLICT ? this.pal.DANGER : this.pal.OK)

              Text(row.draft.content.substring(0, 100).replace(/\n/g, '⏎'))
                .fontSize(11)
                .fontColor(this.pal.TEXT_FAINT)
                .maxLines(2)

              Flex({ wrap: FlexWrap.Wrap }) {
                if (row.decision === RecoveryDecision.RESTORE_DRAFT) {
                  Button('恢复', { type: ButtonType.Normal })
                    .attributeModifier(new ControlStyle(this.pal, 'primary'))
                    .width(96).margin({ right: 8, top: 4 }).onClick(() => this.restoreRow(row))
                }
                Button('另存副本', { type: ButtonType.Normal })
                  .attributeModifier(new ControlStyle(this.pal, 'quiet'))
                  .width(96).margin({ right: 8, top: 4 }).onClick(() => this.saveCopy(row))
                Button(row.decision === RecoveryDecision.DISCARD_REDUNDANT ? '确认清理' : '放弃草稿', { type: ButtonType.Normal })
                  .attributeModifier(new ControlStyle(this.pal, 'danger'))
                  .width(96).margin({ right: 8, top: 4 }).onClick(() => this.discardRow(row))
              }
              .width('100%')
            }
            .padding(10)
            .backgroundColor(this.pal.CONTENT)
            .borderRadius(ControlMetrics.RADIUS)
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
        }, (row: DraftRow) => row.draft.documentId)
      }
      .layoutWeight(1)
      .width('100%')
      }
      .padding(16)
      .width('100%')
      .constraintSize({ maxWidth: 760 })
      .height('100%')
      .backgroundColor(this.pal.BG)
    }
    }
    .width('100%')
    .height('100%').padding({ top: this.captionBottom })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.pal.BG)
  }
  build() { Column() { SafePage() { this.pageContent() } }.width('100%').height('100%') }
}
