import { deviceInfo } from '@kit.BasicServicesKit';

/** 原生 Web 交互开关按 API 版本启用；旧系统保留默认触摸菜单。 */
export class WebDragStyle implements AttributeModifier<WebAttribute> {
  applyNormalAttribute(web: WebAttribute): void {
    if (deviceInfo.sdkApiVersion >= 24) { web.enableDefaultContextMenu(true); }
    if (typeof deviceInfo.apiAvailable === 'function') {
      if (deviceInfo.apiAvailable('26.0.0')) {
        web.enableDrag(false);
      }
    }
  }
}
