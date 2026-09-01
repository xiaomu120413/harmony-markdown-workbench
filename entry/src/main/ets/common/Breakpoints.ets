import { mediaquery } from '@kit.ArkUI';

/**
 * 三档布局断点（产品化多端，V0.1）。
 *   phone  < 600vp   手机竖屏 / 分屏小窗      → 单栏紧凑
 *   tablet 600–959vp 手机横屏 / 平板竖屏 / 小自由窗 → 双栏
 *   pc     ≥ 960vp   平板横屏 / PC 自由窗口     → 宽内容（三栏/居中限宽）
 */
export type Breakpoint = 'phone' | 'tablet' | 'pc';

const QUERY_PHONE = '(max-width: 599vp)';
const QUERY_TABLET = '(min-width: 600vp) and (max-width: 959vp)';
const QUERY_PC = '(min-width: 960vp)';

/** mediaquery 档位快照（同步） */
export function bpOf(): Breakpoint {
  const pc = mediaquery.matchMediaSync(QUERY_PC);
  if (pc.matches) {
    return 'pc';
  }
  const tab = mediaquery.matchMediaSync(QUERY_TABLET);
  if (tab.matches) {
    return 'tablet';
  }
  return 'phone';
}

/** mediaquery 三档监听 */
export function watchBreakpoints(cb: (bp: Breakpoint) => void): mediaquery.MediaQueryListener[] {
  const pc = mediaquery.matchMediaSync(QUERY_PC);
  const tab = mediaquery.matchMediaSync(QUERY_TABLET);
  const ph = mediaquery.matchMediaSync(QUERY_PHONE);
  const fire = (): void => {
    cb(bpOf());
  };
  pc.on('change', fire);
  tab.on('change', fire);
  ph.on('change', fire);
  fire();
  return [pc, tab, ph];
}

export function unwatchBreakpoints(listeners: mediaquery.MediaQueryListener[]): void {
  for (let i = 0; i < listeners.length; i++) {
    listeners[i].off('change');
  }
}