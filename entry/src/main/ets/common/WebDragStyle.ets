import { deviceInfo } from '@kit.BasicServicesKit';

/** 最低 API 24 启用原生菜单；拖动控制仍按 API 26 门控。 */
export class WebDragStyle implements AttributeModifier<WebAttribute> {
  applyNormalAttribute(web: WebAttribute): void {
    web.enableDefaultContextMenu(true);
    if (typeof deviceInfo.apiAvailable === 'function') {
      if (deviceInfo.apiAvailable('26.0.0')) {
        web.enableDrag(false);
      }
    }
  }
}
