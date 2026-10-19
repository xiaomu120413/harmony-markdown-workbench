import { AppTheme } from './AppTheme';
import { ControlStyle } from './ControlStyle';

/**
 * 分段选择按钮（V0.2.2）。
 * 用 @Component + @Prop 而非 @Builder 实现：@Builder 按值传参时内部
 * 属性绑定不随参数变化刷新（active 高亮/调色板切换会停留在旧值）；
 * 组件的 @Prop 在父状态变化时正确重渲染。
 */
@Component
export struct SegBtn {
  @Prop label: string = '';
  @Prop active: boolean = false;
  @Prop pal: AppTheme = AppTheme.light();
  action: () => void = () => {};

  build() {
    Button(this.label, { type: ButtonType.Normal })
      .attributeModifier(new ControlStyle(this.pal, this.active ? 'selected' : 'quiet', this.label === '−' || this.label === '+'))
      .accessibilitySelected(this.active)
      .onClick(() => this.action())
  }
}
