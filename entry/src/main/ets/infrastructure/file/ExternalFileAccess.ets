import { MuLogger } from '../../common/MuLogger';
import { fileShare } from '@kit.CoreFileKit';

/** Only retain the exact URI already granted by the system picker/open-with flow. */
export class ExternalFileAccess {
  private static supported(): boolean {
    return canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization');
  }

  static async prepare(uri: string): Promise<boolean> {
    if (!ExternalFileAccess.supported()) {
      MuLogger.info('persistent access unavailable; using temporary grant');
      return false;
    }
    for (const mode of [fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE,
      fileShare.OperationMode.READ_MODE]) {
      const policies: fileShare.PolicyInfo[] = [{ uri: uri, operationMode: mode }];
      try {
        const granted = await fileShare.checkPersistentPermission(policies);
        if (granted[0] !== true) { await fileShare.persistPermission(policies); }
        await fileShare.activatePermission(policies);
        MuLogger.info(`persistent access active, mode=${mode}`);
        return true;
      } catch (e) {
        const error: ESObject = e as ESObject;
        // URI and platform error messages can contain private paths; log only the code.
        MuLogger.warn(`persistent access failed, mode=${mode} code=${String(error.code ?? 'unknown')}`);
      }
    }
    return false;
  }

  static async isPersistent(uri: string): Promise<boolean> {
    if (!ExternalFileAccess.supported()) { return false; }
    try {
      const result = await fileShare.checkPersistentPermission([
        { uri: uri, operationMode: fileShare.OperationMode.READ_MODE }]);
      return result[0] === true;
    } catch (e) {
      const error: ESObject = e as ESObject;
      MuLogger.warn(`persistent access check failed, code=${String(error.code ?? 'unknown')}`);
      return false;
    }
  }
}
