export interface SafeRect { left: number; top: number; width: number; height: number; }
export interface AvoidanceRects { leftRect: SafeRect; topRect: SafeRect; rightRect: SafeRect; bottomRect: SafeRect; }
export interface SafeInsets { left: number; top: number; right: number; bottom: number; }

/** Native rectangles are window-relative pixels. Overlapping sources take max, never sum. */
export class SafeAreaPolicy {
  static resolve(areas: AvoidanceRects[], width: number, height: number, density: number): SafeInsets {
    const scale = density > 0 ? density : 1;
    const result: SafeInsets = { left: 0, top: 0, right: 0, bottom: 0 };
    for (const area of areas) {
      if (area.leftRect.width > 0 && area.leftRect.height > 0) {
        result.left = Math.max(result.left, Math.min(width, area.leftRect.left + area.leftRect.width) / scale);
      }
      if (area.topRect.width > 0 && area.topRect.height > 0) {
        result.top = Math.max(result.top, Math.min(height, area.topRect.top + area.topRect.height) / scale);
      }
      if (area.rightRect.width > 0 && area.rightRect.height > 0) {
        result.right = Math.max(result.right, Math.min(width, width - area.rightRect.left) / scale);
      }
      if (area.bottomRect.width > 0 && area.bottomRect.height > 0) {
        result.bottom = Math.max(result.bottom, Math.min(height, height - area.bottomRect.top) / scale);
      }
    }
    return result;
  }
}
