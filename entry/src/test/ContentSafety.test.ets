import { describe, expect, it } from '@ohos/hypium';
import { SaveCoordinator, SaveCoordinatorDeps, SnapshotData } from '../main/ets/services/SaveCoordinator';
import { SaveState } from '../main/ets/domain/recovery/SaveStateMachine';
import { WriteDocumentResult } from '../main/ets/domain/document/DocumentFileAdapter';
import { AttachmentPlan } from '../main/ets/domain/document/AttachmentPlan';

class SafetyDeps implements SaveCoordinatorDeps {
  content: string = '初稿';
  version: number = 1;
  sessionId: string = 'session';
  checkpoint: string = '';
  saved: string = '';
  failCheckpoint: boolean = false;
  snapshotOk: boolean = true;
  editDuringPersist: boolean = false;
  cleanup: number = 0;
  async getSnapshot(): Promise<SnapshotData> {
    return { ok: this.snapshotOk, sessionId: this.sessionId, version: this.version, content: this.content };
  }
  async saveCheckpoint(content: string): Promise<void> {
    if (this.failCheckpoint) { throw new Error('disk full'); }
    this.checkpoint = content;
  }
  async persist(content: string): Promise<WriteDocumentResult> {
    this.saved = content;
    if (this.editDuringPersist) { this.version++; this.content = '保存期间的新输入'; }
    return { ok: true, revision: { size: content.length, contentHash: 'saved' } };
  }
  async clearCheckpoint(): Promise<void> { this.cleanup++; }
}

export default function contentSafetyTest(): void {
  describe('ContentSafety', () => {
    it('snapshot_detects_edit_before_bridge_notification', 0, async () => {
      const d = new SafetyDeps(); const c = new SaveCoordinator(d);
      expect(await c.checkpointNow()).assertTrue();
      expect(c.state).assertEqual(SaveState.DIRTY); expect(d.checkpoint).assertEqual('初稿');
    });
    it('late_event_for_saved_version_is_ignored', 0, () => {
      const d = new SafetyDeps(); const c = new SaveCoordinator(d); c.onDocumentLoaded('session', 3);
      c.onEdit(100, 3); expect(c.state).assertEqual(SaveState.CLEAN);
    });
    it('checkpoint_without_autosave_does_not_write_original', 0, async () => {
      const d = new SafetyDeps(); const c = new SaveCoordinator(d); c.onEdit(100, 1);
      expect(await c.checkpointNow()).assertTrue();
      expect(d.checkpoint).assertEqual('初稿'); expect(d.saved).assertEqual('');
      expect(c.state).assertEqual(SaveState.DIRTY);
    });
    it('checkpoint_failure_prevents_source_write', 0, async () => {
      const d = new SafetyDeps(); d.failCheckpoint = true;
      const c = new SaveCoordinator(d); c.onEdit(100, 1);
      expect(await c.saveNow(200)).assertEqual('failed'); expect(d.saved).assertEqual('');
    });
    it('late_edit_notification_cannot_clear_new_content', 0, async () => {
      const d = new SafetyDeps(); d.editDuringPersist = true;
      const c = new SaveCoordinator(d); c.onEdit(100, 1);
      await c.saveNow(200);
      expect(c.state).assertEqual(SaveState.DIRTY); expect(d.cleanup).assertEqual(0);
      expect(d.checkpoint).assertEqual('保存期间的新输入');
    });
    it('old_session_cannot_write_checkpoint', 0, async () => {
      const d = new SafetyDeps(); const c = new SaveCoordinator(d); c.onDocumentLoaded('new-session');
      expect(await c.checkpointNow()).assertFalse(); expect(d.checkpoint).assertEqual('');
    });
    it('snapshot_failure_preserves_previous_checkpoint', 0, async () => {
      const d = new SafetyDeps(); const c = new SaveCoordinator(d);
      await c.checkpointNow(); d.snapshotOk = false;
      expect(await c.checkpointNow()).assertFalse(); expect(d.checkpoint).assertEqual('初稿');
    });
    it('completed_version_can_cleanup_checkpoint', 0, async () => {
      const d = new SafetyDeps(); const c = new SaveCoordinator(d); c.onEdit(0, 1);
      expect(await c.saveNow(100)).assertEqual('saved'); expect(d.cleanup).assertEqual(1);
    });
    it('attachment_plan_decodes_spaces_and_deduplicates', 0, () => {
      const p = AttachmentPlan.create(['attachments/a%20b.png', 'attachments/a%20b.png', 'https://example.com/x.png']);
      expect(p.local.length).assertEqual(1); expect(p.local[0].name).assertEqual('a b.png'); expect(p.remote).assertTrue();
    });
    it('attachment_plan_rejects_traversal_and_ungranted_paths', 0, () => {
      for (const source of ['attachments/../x.png', 'attachments/%2e%2e%2fx.png', 'file:///secret.png', '../photo.png']) {
        let failed = false; try { AttachmentPlan.create([source]); } catch (e) { failed = true; }
        expect(failed).assertTrue();
      }
    });
  });
}
