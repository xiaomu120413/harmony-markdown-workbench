# 木笺 MuMark

完全离线的 HarmonyOS Markdown 编辑器。规格与执行合同见 `HarmonyMarkdownWorkbench-SDD.md`（SDD 1.0.0），开发遵循 Specification-Driven Development 流程。

**产品原则：打开的是原文件，保存后仍是原文件。**

本轮名称统一为 **木笺 MuMark**，与木枢、MuTransfer 同系列。
[使用说明](docs/user-guide.md) · [本轮规格](docs/spec/productization-2026-10.md) · [验证与限制](docs/spec/productization-verification.md) · [图标母版](docs/brand/README.md)。
本轮交付以验证记录为准，下表旧版本“完成”不替代当前设备与异常路径的验收。
后续改进：[外部文件入口与操作分组](docs/spec/file-intake-2026-10.md) · [真实授权、拖入与菜单验收](docs/spec/file-intake-verification.md)。
文档操作更新：[宽窄屏设计](docs/spec/document-actions-2026-10.md) · [面板验收](docs/spec/document-actions-verification.md)。
界面一致性：[全局控件规则](docs/spec/control-system-2026-10.md) · [截图审查与验收](docs/spec/control-system-verification.md)。
整体复查：[窄窗快捷键与帮助修正](docs/spec/final-review-2026-10.md)。
状态与授权：[状态精简、持久授权与设置帮助](docs/spec/state-access-2026-10.md)。当前声明单文件持久访问权限 `ohos.permission.FILE_ACCESS_PERSIST`，历史“零权限”记录不代表当前版本。

## 当前状态

| 里程碑 | 状态 | 说明 |
|---|---|---|
| M0 四尖峰 | ✅ 完成 | 外部 URI 授权链、ArkWeb 编辑器运行时、原子写与草稿恢复，真机验证 |
| M1 文件模型 | ✅ 完成 | 内/外适配器契约 10/10、元数据（最近/固定/淘汰）、资料库增删改查，真机验证 |
| M2 编辑器 | ✅ 完成 | CodeMirror 6.x 运行时、桥协议、快捷栏命令、保存状态机接入，真机验证 |
| M3 预览 | ✅ 完成 | markdown-it GFM 渲染、恶意语料转义不执行、大纲/查找，真机验证 |
| M4 保存链 | ✅ 完成 | SaveCoordinator 编排、自动保存防抖、外部冲突三决策、崩溃恢复入口，真机验证 |
| M5 工作台 | ✅ 完成 | 首页（最近/打开/恢复入口）、分享（剪贴板降级，API 26 无 ShareKit）、设置持久化，真机验证 |
| M6 质量 | ✅ 完成 | 窄窗响应式、性能样本 S1–S4 实测、隐私扫描零权限、Release 构建装机，真机验证 |
| V0.2 三端总装 | ✅ 完成（2026-10-10） | **预览/分屏接入生产编辑器**（phone 切换、tablet/PC 分屏）、**查找替换面板**、**桥协议修复**（打字→自动保存链路）、撤销重做、defaultView 消费、deviceTypes 补 2in1、Spike 页面清出发布包；三端断点真机逐档验证（详见 acceptance.md V0.2 节） |
| V0.2.1 编辑完整性 | ✅ 完成（2026-10-10） | **标题等级 H1–H3 快捷命令**（h1–h6 同级取消/异级切换）、分隔线/表格/图片按钮、**大纲导航面板**（点击跳转标题行）、**系统标题栏隐藏**（应用内标题区接管窗口拖动）；真机验证（acceptance.md V0.2.1 节） |
| V0.2.2 产品化 | ✅ 完成（2026-10-10） | **示例按钮等开发痕迹清除**、**智能文档命名**（首行作标题 + 自动名升级重命名）、**全局深色主题**（四页全 chrome 跟随）、设置即改即存（三区卡片）、工具栏分组、首页/恢复页文案与交互打磨；真机验证（acceptance.md V0.2.2 节） |
| V0.2.3 显示修复 + 外部打开 | ✅ 完成（2026-10-12） | **外部文件打开**（系统选择器 .md/.txt → 原位读写，产品原则主链路）、最近列表干净文件名、设置/恢复页宽屏居中、深色模式编辑器行号/激活行补全；真机验证（acceptance.md V0.2.3 节） |
| V0.3 视觉重设计 | ✅ 完成（2026-10-12） | **卡片化工作台**：首页侧栏 + 主区双栏 shell（phone 单栏 + 文字 Tab）、编辑器顶栏重排、工具栏中文标签分组（替代符号墙）、emoji 移除、MD 徽标图标语言；三档真机验证（acceptance.md V0.3 节） |
| V0.4 原生设计语言 | ✅ 完成（2026-10-13） | **对齐系统备忘录提取的「色调分层」范式**：三档色调（侧栏/列表/内容）替代描边卡片、首页三区（侧栏｜最近列表｜欢迎区）、编辑器平铺化、设置页系统分组行风格；真机验证（acceptance.md V0.4 节） |
| V0.4.1 Markdown 功能对齐 | ✅ 完成（2026-10-13） | **标题等级工具栏全量 H1–H6**、**嵌套列表缩进/减少缩进**；CommonMark+GFM 语法全覆盖（HTML 安全禁用） |
| V0.4.2 编辑器能力补齐 | ✅ 完成（2026-10-13） | **状态栏**（字数/行列/标题数）、**高亮 ==text== 与脚注 [^1] 语法**、**分享菜单**（复制 Markdown/渲染 HTML）、**资料库管理**（重命名/回收站删除）；详见 acceptance.md V0.4.2 节 |
| V0.4.3 搜索/导出/帮助 | ✅ 完成（2026-10-15） | **资料库全文搜索**（防抖 + 摘要 + 命中数，宽屏/phone 双入口）、**导出 HTML 文件**（自包含样式 + 系统保存选择器）、**快捷键与提示面板**；详见 acceptance.md V0.4.3 节 |
| V0.4.4 复审修正 | ✅ 完成（2026-10-15） | 独立审计缺陷修复（帮助换行/窗口僵死/样式竞态/零反馈）、**回收站可见可恢复**、去模板化视觉（安静欢迎区/去箭头与 emoji 图标）；已知未收口项显式记录于 acceptance.md V0.4.4 节 |

验收追踪：`docs/spec/acceptance.md`；性能报告：`docs/spec/performance.md`；风险与决策：`docs/risks.md`、`docs/adr/`。

## 环境要求

- DevEco Studio 6.x（本机验证：DevEco Studio 6.6，SDK `ets` API 26 / HarmonyOS 6.6.0 Beta1）
- JDK：DevEco Studio 自带 jbr（`JAVA_HOME` 指向 DevEco 的 `jbr`）
- Node.js ≥ 18（本机验证：v25.5.0）
- 环境变量（DevEco Studio 安装后 IDE 会设置）：

  | 变量 | 期望值 |
  |---|---|
  | `DEVECO_STUDIO_PATH` | DevEco Studio 安装根目录，如 `C:\Program Files\Huawei\DevEco Studio` |
  | `DEVECO_SDK_HOME` | 如 `C:\Program Files\Huawei\DevEco Studio\sdk` |
  | `NODE_HOME` | Node 安装目录，如 `C:\Program Files\nodejs` |

  工程内 `hvigorw` / `hvigorw.bat` 是转发脚本：优先使用 `DEVECO_STUDIO_PATH`，未设置时探测默认安装位置。

## 常用命令（Windows）

以下命令在工程根目录执行。`hvigorw.bat` 用于 cmd，Git Bash 中可用 `./hvigorw`。

```bat
:: 构建 Debug HAP（unsigned）
hvigorw.bat assembleHap --mode module -p product=default

:: 运行单元测试（hypium，本地执行，无需设备）
hvigorw.bat test --mode module -p product=default

:: 全清重建 + 测试门禁（模拟无缓存环境，CI 等价验证）
scripts\clean-build.bat
```

Git Bash：

```bash
./hvigorw assembleHap --mode module -p product=default
./hvigorw test --mode module -p product=default
bash scripts/clean-build.sh
```

产物位置：`entry/build/default/outputs/default/entry-default-unsigned.hap`

构建/测试日志：`build-logs/clean-build.log`（`build/` 与 `entry/build/` 由 hvigor 管理，勿手工写入）。

## 质量门禁

| 门禁 | 方式 | 现状 |
|---|---|---|
| 编译严格性 | `build-profile.json5` strictMode（大小写敏感、规范化 OHM URL） | ✅ |
| 单元测试 | hypium 1.0.21（`entry/src/test/`），`hvigorw test` | ✅ |
| 测试失败拦截 | `clean-build` 脚本检查测试日志中的 hypium 断言 ERROR（hypium 用例失败时 hvigor 任务仍返回成功，见风险 R-07） | ✅ |
| 无缓存构建 | `scripts/clean-build.sh` / `.bat`：删缓存→ohpm install→构建→测试 | ✅ |
| CI | `.github/workflows/ci.yml` 预留，需自托管 runner（GitHub-hosted 无 HarmonyOS SDK，见 R-06） | ⚠️ 未实机运行 |
| 静态检查/格式化 | DevEco IDE 内置 Code Linter 与格式化；命令行无等价工具（R-05） | ⚠️ 需 IDE |

## 目录结构

```
entry/src/main/ets/
├── pages/            首页、编辑器、设置和恢复页面
├── features/         首页/编辑器状态、平台依赖、功能控制器与分区视图（每文件 ≤500 行）
├── components/       ArkUI 可复用组件（各层 README 写明职责与规划任务）
├── domain/           领域模型与规则（document/recovery/settings）
├── services/         服务编排（DocumentService/SaveCoordinator/EditorBridge…）
├── infrastructure/   平台实现（file/metadata/recovery）
└── web/              职责说明；源码在 web-tools，包资源在 resources/rawfile/web
docs/                 规格、ADR、风险、计划（见「相关文档」）
scripts/              clean-build、图标生成等脚本
```

层次职责与约束详见各层 `README.md`（对应 SDD 8.1）。

## 签名说明

工程保持 `signingConfigs` 为空（hvigor 6 密码为 IDE 加密格式，明文不入库），构建产 unsigned HAP。真机安装包用本地签名脚本生成：

```bash
# 生成官方 OpenHarmony CA 签名的安装包（材料在工程外 ../local-sign/，勿入库）
bash scripts/sign-local.sh entry/build/default/outputs/default/entry-default-unsigned.hap
```

签名链路（app 证书由 OpenHarmony Application CA 签发、profile 由官方 Profile Debug CA 签发）已在 M0-02 尖峰完整打通，详见 `docs/spikes/external-uri.md`。

**注意（R-11）**：本开发机（MateBook Pro，华为定制 OpenHarmony 7.0 镜像）信任库不含 Profile CA 且 erofs 只读，**不接受第三方调试签名安装**；功能验证需可调试镜像/设备或华为发布签名。正式发布签名（M6-04）经 AppGallery 配置，密钥一律不入库。

## 相关文档

- `docs/spec/product-spec.md` — 产品规格（稳定版）
- `docs/spec/acceptance.md` — 需求到验收用例映射
- `docs/adr/` — 技术决策记录（001–005 来自 SDD，006–008 为 M0-01 新决策）
- `docs/risks.md` — 风险清单（含本机实测发现）
- `docs/plan.md` — 里程碑与任务计划
- `docs/assumptions.md` — Clarify 阶段默认值与假设
- `docs/spikes/` — M0 技术尖峰输出目录

## 本轮验证

```powershell
npm.cmd ci --prefix web-tools --no-audit --no-fund
node web-tools/build-web.js
node scripts/test-host.cjs
node scripts/test-editor-actions.cjs
node scripts/test-file-transactions.cjs
node scripts/test-external-access.cjs
node scripts/test-page-viewmodels.cjs
node scripts/test-window-viewport.cjs
node scripts/check-source-size.mjs
```

宿主测试执行真实领域源码并注入平台 IO 故障，不替代 ArkTS 编译和真机验收。
另存为、图文 ZIP、HTML 和系统打开的实际证据及签名限制见[验证记录](docs/spec/productization-verification.md)。
手机/平板安全区、软键盘策略、职责拆分与设备验收见[本轮适配记录](docs/spec/mobile-adaptation-2026-10.md)。
拆分后打开、拖入、保存、导出及实际产物核对见[文件链路回归记录](docs/spec/file-regression-2026-10.md)。
API 22 实体平板与 MVVM 全局边界检查见[平板验收记录](docs/spec/tablet-mvvm-2026-10.md)。
