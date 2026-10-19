import { deviceInfo } from '@kit.BasicServicesKit';

/** API 22–25 没有 enableDrag；门控检查本身也必须兼容旧系统。 */
export class WebDragStyle implements AttributeModifier<WebAttribute> {
  applyNormalAttribute(web: WebAttribute): void {
    if (typeof deviceInfo.apiAvailable === 'function') {
      if (deviceInfo.apiAvailable('26.0.0')) {
        web.enableDrag(false);
      }
    }
  }
}
