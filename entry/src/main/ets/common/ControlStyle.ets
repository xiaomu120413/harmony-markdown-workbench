import { AppTheme } from './AppTheme';

/** 同类操作共用尺寸；列表行、系统开关与系统菜单不套按钮尺寸。 */
export class ControlMetrics {
  static readonly HEIGHT: number = 44;
  static readonly MIN_WIDTH: number = 72;
  static readonly RADIUS: number = 6;
  static readonly FONT: number = 14;
}

export type ControlRole = 'quiet' | 'primary' | 'selected' | 'secondary' | 'danger';

/** 保留原生 Button 的语义、焦点、禁用与菜单能力，只收敛视觉属性。 */
export class ControlStyle implements AttributeModifier<ButtonAttribute> {
  private readonly pal: AppTheme;
  private readonly role: ControlRole;
  private readonly icon: boolean;

  constructor(pal: AppTheme, role: ControlRole = 'quiet', icon: boolean = false) {
    this.pal = pal;
    this.role = role;
    this.icon = icon;
  }

  applyNormalAttribute(button: ButtonAttribute): void {
    const primary = this.role === 'primary';
    const selected = this.role === 'selected';
    button.height(ControlMetrics.HEIGHT)
      .constraintSize({ minWidth: this.icon ? ControlMetrics.HEIGHT : ControlMetrics.MIN_WIDTH })
      .fontSize(ControlMetrics.FONT).fontWeight(primary || selected ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(primary ? this.pal.ON_PRIMARY : this.role === 'danger' ? this.pal.DANGER : selected ? this.pal.PRIMARY : this.pal.TEXT)
      .backgroundColor(primary ? this.pal.PRIMARY : selected ? this.pal.PRIMARY_SOFT
        : this.role === 'secondary' ? this.pal.CONTENT : Color.Transparent)
      .border({ width: this.role === 'secondary' ? 1 : 0, color: this.pal.DIVIDER })
      .borderRadius(ControlMetrics.RADIUS).padding({ left: 12, right: 12 })
      .hoverEffect(HoverEffect.Highlight);
    if (this.icon) { button.width(ControlMetrics.HEIGHT).padding(10); }
  }
}
