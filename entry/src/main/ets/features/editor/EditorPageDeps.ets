import { SaveCoordinatorDeps, SnapshotData } from '../../services/SaveCoordinator';
import { WriteDocumentResult } from '../../domain/document/DocumentFileAdapter';
export class EditorPageDeps implements SaveCoordinatorDeps {
  private readonly snapshotImpl: () => Promise<SnapshotData>;
  private readonly checkpointImpl: (c: string) => Promise<void>;
  private readonly cleanupImpl: () => Promise<void>;
  private readonly persistImpl: (c: string) => Promise<WriteDocumentResult>;

  constructor(
    snapshotImpl: () => Promise<SnapshotData>,
    checkpointImpl: (c: string) => Promise<void>,
    persistImpl: (c: string) => Promise<WriteDocumentResult>,
    cleanupImpl: () => Promise<void>,
  ) {
    this.snapshotImpl = snapshotImpl;
    this.checkpointImpl = checkpointImpl;
    this.persistImpl = persistImpl;
    this.cleanupImpl = cleanupImpl;
  }

  clearCheckpoint(): Promise<void> { return this.cleanupImpl(); }

  getSnapshot(): Promise<SnapshotData> {
    return this.snapshotImpl();
  }

  saveCheckpoint(content: string): Promise<void> {
    return this.checkpointImpl(content);
  }

  persist(content: string): Promise<WriteDocumentResult> {
    return this.persistImpl(content);
  }
}
