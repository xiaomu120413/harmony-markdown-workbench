import { unifiedDataChannel, uniformDataStruct } from '@kit.ArkData';
import { DocumentIntake } from '../domain/document/DocumentIntake';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 拖放必须异步获取系统授权数据，避免同步 UDMF 取数阻塞页面。 */
export class DroppedDocumentReader {
  static receive(event: DragEvent, timeoutMs: number = 15000, destUri: string = '',
    cancel: (key: string) => void = () => {}): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      let finished = false;
      let key = '';
      const timer = setTimeout(() => {
        if (!finished) {
          finished = true;
          try { if (key.length > 0) { cancel(key); } }
          catch (e) { hilog.warn(0, 'MUMARK-DROP', 'cancel data loading failed'); }
          reject(new Error('读取拖入文件超时，请重试或使用“打开文档”'));
        }
      }, timeoutMs);
      try {
        key = event.startDataLoading({
          destUri: destUri.length > 0 ? destUri : undefined,
          progressIndicator: unifiedDataChannel.ProgressIndicator.NONE,
          dataProgressListener: (progress: unifiedDataChannel.ProgressInfo, data: unifiedDataChannel.UnifiedData | null) => {
            hilog.info(0, 'MUMARK-DROP', 'data status=%{public}d progress=%{public}d present=%{public}s', progress.status, progress.progress, String(data !== null));
            if (finished || progress.status === unifiedDataChannel.ListenerStatus.PROCESSING) { return; }
            finished = true;
            clearTimeout(timer);
            if (data === null || progress.status !== unifiedDataChannel.ListenerStatus.FINISHED) {
              reject(new Error('无法取得拖入文件的访问授权，请使用“打开文档”')); return;
            }
            try { resolve(DocumentIntake.select(DroppedDocumentReader.uris(data))); }
            catch (e) { reject(e); }
          },
        });
      } catch (e) { finished = true; clearTimeout(timer); reject(e); }
    });
  }

  private static uris(data: unifiedDataChannel.UnifiedData): string[] {
    const uris: string[] = [];
    for (const record of data.getRecords()) {
      if (record.getTypes().includes('general.file-uri')) {
        const value = record.getEntry('general.file-uri') as uniformDataStruct.FileUri;
        uris.push(value.oriUri);
      } else {
        const file = record as unifiedDataChannel.File;
        if (typeof file.uri === 'string' && file.uri.length > 0) { uris.push(file.uri); }
      }
    }
    return uris;
  }
}
