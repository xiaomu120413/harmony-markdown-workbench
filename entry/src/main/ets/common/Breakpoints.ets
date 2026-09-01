import { mediaquery } from '@kit.ArkUI';

/**
 * 三档布局断点（产品化多端，V0.1）。
 *   phone  < 600vp   手机竖屏 / 分屏小窗      → 单栏紧凑
 *   tablet 600–959vp 手机横屏 / 平板竖屏 / 小自由窗 → 双栏
 *   pc     ≥ 960vp   平板横屏 / PC 自由窗口     → 宽内容（三栏/居中限宽）
 * 统一使用 vp 单位（此前使用 px 物理像素判定在 3.25x 设备上会将 258vp 宽度
 * 误判为宽屏——本工具修正该语义错误）。
 */
export type Breakpoint = 'phone' | 'tablet' | 'pc';

const QUERY_PHONE = '(max-width: 599vp)';
const QUERY_TABLET = '(min-width: 600vp) and (max-width: 959vp)';
const QUERY_PC = '(min-width: 960vp)';

/** 按当前视口宽度取档位 */
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

/**
 * 注册三档监听；返回监听器列表，页面 aboutToDisappear 时应调用
 * unwatchBreakpoints 释放。回调在档位变化时触发（首次立即回调一次）。
 */
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