# Harmony Markdown Workbench

HarmonyOS 原生 Markdown 文件工作台（V0.1 MVP）。规格与执行合同见 `HarmonyMarkdownWorkbench-SDD.md`（SDD 1.0.0），开发遵循 Specification-Driven Development 流程。

**产品原则：打开的是原文件，保存后仍是原文件。**

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
├── pages/            页面（HomePage 当前为 M0-01 占位，M5-01 实现首页）
├── components/       ArkUI 可复用组件（各层 README 写明职责与规划任务）
├── domain/           领域模型与规则（document/recovery/settings）
├── services/         服务编排（DocumentService/SaveCoordinator/EditorBridge…）
├── infrastructure/   平台实现（file/metadata/recovery）
└── web/              ArkWeb 编辑运行时资源（M2 起填充）
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

## 下一步

M0-02：外部文件 URI 尖峰（验证选择/读取/重启持久访问/原位保存/权限失效），输出 `docs/spikes/external-uri.md`。