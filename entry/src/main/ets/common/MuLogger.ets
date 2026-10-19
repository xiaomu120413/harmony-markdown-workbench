import { hilog } from '@kit.PerformanceAnalysisKit';

/** Same static facade and private messages as 木枢's RdpLogger. */
export class MuLogger {
  static debug(line: string): void { hilog.debug(0, 'MuMark', '%{private}s', line); }
  static info(line: string): void { hilog.info(0, 'MuMark', '%{private}s', line); }
  static warn(line: string): void { hilog.warn(0, 'MuMark', '%{private}s', line); }
  static error(line: string): void { hilog.error(0, 'MuMark', '%{private}s', line); }
}
