# 全局控件与视觉收敛

2026-10-19，TASK-CONTROLS-001；承接用户对全局尺寸、颜色不一致的反馈。基线 d01ad91，工作区干净。

## 需求

| ID | 可验收行为 |
|---|---|
| FR-CONTROLS-001 | 首页、编辑、设置、恢复及文档侧栏共用按钮规则：标准操作高 44vp、字号 14fp、圆角 8vp；图标按钮 44×44，文本按钮至少 72vp；同组同高、相同短标签同宽 |
| FR-CONTROLS-002 | 主要动作使用同一蓝色；普通操作使用中性色、选中状态使用浅色选中底；移除胶囊/小色块混搭和正常“已保存”的彩色徽章。危险操作仍明确使用危险色。深浅主题均可辨认 |
| FR-CONTROLS-003 | 宽窗编辑标题与命令工具栏分层，系统三键留出空间；窄窗保留标题、保存与操作面板，命令栏横向滚动。设置内容有最大宽度，恢复操作窄窗可换行 |
| FR-CONTROLS-004 | 点击、菜单、键盘焦点、保存、主题切换及恢复入口不丢失。多行面板操作行至少 56vp，原生开关、系统菜单及底部导航按各自控件规则，不冒充 44vp 按钮 |

非目标：重写业务、目录工作区、正式签名迁移和全量手机认证。

## 设计与任务

以现有 ArkUI 原生界面为视觉目标；统一 AppTheme 与共享 ControlStyle / ControlMetrics，沿用原生 Button、hover 与 focus，不做新插画、渐变或装饰性卡片。使用当前 SDK 的 AttributeModifier<ButtonAttribute> 保留 native Button 及 bindMenu/bindSheet 生命周期。选择 ArkTS 是因为本任务仅涉及 ArkUI 属性与组件。

单一任务 TASK-CONTROLS-001 修改四页、SegBtn、DocumentSidebar、AppTheme 和窗口三键布局参数，沿用保存/交付服务；同提交包含审查证据、说明和验证。无持久化结构变化，可按提交回退。

## 授权与分包评估

本轮界面一致性无需新权限或新 HAP。用户允许需要时授权及分包，不等于应无条件新增。现有 entry 服务 phone/tablet/2in1；当前服务只接收用户选择/交付的文件，未增加扫描公共目录功能。

目录工作区需要单独定义目录范围、撤权、重启恢复及附件路径规则后实现。若采用 2in1 专属目录能力，可评估多设备分发，公用编辑与保存逻辑保持共用；不复制出两份业务。参考[官方应用包说明](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/application-package-glossary)和[跨 HAP 方案](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-package-structure-76)。此处是设计判断，不声称已经分包或获得目录访问权。

## 验证

先截图审查各页，再实施并在同尺寸窗口对照；验证宽/窄窗和深浅色、菜单、查找、视图与设置。运行现有宿主测试、Hvigor test、Debug/Release 构建及文档检查，不为样式写镜像单测。结果见[审查与验收](control-system-verification.md)。
