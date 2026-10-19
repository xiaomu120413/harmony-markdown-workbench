# 编码、布局与分包兼容性复查

2026-10-19，TASK-COMPAT-001；基线 4862f48。目标仓库 harmony-markdown-workbench，非 log_tool。

## 需求与实现边界

- FR-COMPAT-001：保留最低 API 22；API 26 Web 拖放属性必须运行时门控，旧版保留原生覆盖层及“打开文档”入口。
- FR-COMPAT-002：600vp / 960vp 断点连续覆盖小数宽度，监听与初始判定一致；首页 tablet 使用导航与最近两栏，避免 250+300vp 固定栏挤坏欢迎区；编辑布局预算扣除外边距与分隔线，展开侧栏或收窄窗口后不能挤坏编辑区，空间不足时收起大纲、退出分屏。
- FR-COMPAT-003：UTF-8 拒绝代理码点，保留合法补充平面字符；恢复草稿必须完整读取并关闭句柄。
- FR-COMPAT-004：记录源码编码、布局与设备证据边界，分清 HAR、HSP、Feature HAP 与设备定制包的风险。

设计：使用 Web AttributeModifier 包装新属性；先判断 apiAvailable 函数存在，再判断版本。断点仅监听两个 min-width，优先宽档，避免 max-width 整数截断。草稿复用 SafeFileIO，不引入存储格式变更。ArkTS 改动属于平台适配与既有领域逻辑；不实际拆模块、不提升最低系统版本、不改包身份及目录。

单一任务 TASK-COMPAT-001：修改 Breakpoints、WebDragStyle、HomePage、EditorPage、ViewModePolicy、TextEncoding、DraftStore；补真实源码执行测试及编码检查。按本提交回滚，无数据迁移。

## 验证记录

环境：Windows PowerShell / DevEco JBR / 当前 API 26 SDK。工作区开始时干净。

| 命令 | 本轮结果 |
|---|---|
| `node scripts/test-host.cjs` | 233/233，通过真实领域源码与平台 IO mock；新增代理码点、分隔线临界值、小数断点/双向变化与监听清理、API 门控、草稿 7 字节短读恢复 |
| `node scripts/test-editor-actions.cjs` | 7 组场景通过；执行当前页面真实方法及真实 ViewModePolicy，覆盖窄窗大纲、面板切换、空间不足拦截、收窄退出分屏等；不代表 ArkUI 渲染 |
| `node scripts/check-source-encoding.mjs` | 145 个源码/配置/文档文本文件严格 UTF-8 解码及 U+FFFD 检查通过；不保证发现所有历史可解码乱码 |
| `node scripts/check-docs.mjs` | 34 个 Markdown UTF-8 与本地链接通过 |
| `hvigorw.bat test --mode module -p product=default` | BUILD SUCCESSFUL，exit 0；日志 `build-logs/compat-test.log` |
| `hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release` | BUILD SUCCESSFUL，exit 0；日志 `build-logs/compat-release.log`；新接口版本告警已消除 |
| `git diff --check` | 通过 |

构建仍存在原有 ESObject 等 ArkTS 警告及未配置正式签名/关闭混淆的提示，不等同于无警告发行包。Release 产物是 `entry/build/default/outputs/default/entry-default-unsigned.hap`。本轮未安装、未执行真机 UI 用例。

FR-COMPAT-001/003：代码、回归与编译通过；API 22–25 真机行为待验证。FR-COMPAT-002：策略/页面方法回归与编译通过；tablet 首页布局待设备目测。FR-COMPAT-004：静态检查与证据边界、分包建议已记录。

## 已修问题与代码质量

1. 最低版本声明为 6.0.2(22)，两处 Web.enableDrag 实际自 API 26 才支持。依据当前 SDK `component/web.d.ts` 与 `api/@ohos.deviceInfo.d.ts` 注解，将属性调用收敛到 WebDragStyle：先检查版本判断函数存在，再单独分支判断版本，旧系统不会调用缺失方法。保留原生拖入覆盖层和文件选择入口；旧版 Web 拖放是否仍阻塞必须真机重测。
2. 原 min/max 整数断点让 959.5vp 错落到 phone。改成嵌套下界区间，两个监听器覆盖所有宽度。
3. tablet 首页原先仍采用 250vp 导航 + 300vp 最近 + 欢迎三栏，600vp 时欢迎区不足 50vp。现在 tablet 仅保留导航和自适应最近两栏；收起最近后才展示欢迎区；pc 保留三栏。
4. 编辑区预算漏算根节点左右 24vp 内边距和分隔线，且展开侧栏/大纲后未重新校验。现在在窗口变化与面板操作后统一校验；空间不足不打开大纲、收起既有大纲或退出分屏，保留用户视图偏好。
5. UTF-8 校验漏掉 U+D800–U+DFFF，可能把不合法字节交给解码器替换。现在拒绝代理码点，验证中文、emoji、合法边界和超范围序列。现有产品支持 UTF-8 / UTF-8 BOM、LF / CRLF；GBK、UTF-16 不属于已支持格式，不能宣传自动兼容全部编码。
6. 草稿读取两处使用一次 readSync，短读会导致 JSON 截断并丢失恢复入口，异常时也可能未关闭 fd。改用已有 SafeFileIO 的完整读取与 finally 关闭，未改变 JSON 格式和目录。

可维护性后续项：EditorPage 约 2100 行，UI、桥接、文件会话与交付编排仍集中；全局 pendingBridge/bridgeSink 和 AppStorage 默认单会话。实际拆多 Ability 前应先抽离会话与交付编排，明确每个会话的草稿、待打开 URI、回调归属；本轮不做跨范围重构。底部状态栏长文本、系统大字体、预览超宽表格/长链接仍需用真实窗口验证。

## 多设备证据与尚未完成的验收

本轮只连接一台 HAD-W32（HUAWEI MateBook Pro，API 26，3120×2080）。11:05 只读截图显示其他应用正在前台使用，因此未抢占窗口。该截图不用于木笺布局通过结论，也未纳入仓库。

既有首页/编辑/设置/恢复的宽窄窗口截图与按钮测量见[控件验收](control-system-verification.md)，是此前 2in1 的证据；不能作为本轮修改后或手机/平板通过的证据。

| 优先级 | 需要的环境 | 必测内容与通过标准 | 当前结论 |
|---|---|---|---|
| P1 | API 22–25 手机/平板 | 冷启动 Web、选择打开、真实授权读写、拖入取消/失败；不调用缺失 API、不冻结 | 未测，不能承诺兼容通过 |
| P1 | 手机真实系统栏/键盘 | 当前 EntryAbility 开启全屏布局，源码没有显式 AvoidArea 适配；检查状态栏/导航手势、软键盘弹出、旋转、底部 sheet 不遮挡正文与按钮 | 静态风险，需设备确认与修复，不以 PC 窄窗代替 |
| P1 | tablet 或 600–959vp 窗口 | 新首页两栏、600/959.x 边界、长文档名、侧栏/大纲/分屏组合、收窄后内容不挤压 | 策略与编译通过，渲染待验 |
| P1 | 2in1 新版本 | 新门控仍能禁止 Web 内建拖放，原生覆盖层接收并导入；宽窄来回与外部打开 | 本轮未部署重验 |
| P2 | 各端大字体/无障碍 | 设置字号、系统字体放大、读屏、键盘焦点、200% 文本；HTML viewport 当前限制缩放，应另行评估 | 未测 |

## 分包兼容性结论

**可以分，但先保留一个 entry HAP；布局问题应先在同包内修好。** 下列为基于现有代码的方案判断，不是已实现能力。

| 方式 | 对木笺的用途 | 主要兼容性成本 | 建议 |
|---|---|---|---|
| HAR 静态库 | 共享领域逻辑、编码/恢复决策、协议；平台适配通过依赖注入 | 多个使用包可能重复打入代码/资源；不能假设不同打包副本共享全局单例 | 真有第二个消费模块时优先考虑 |
| HSP 动态库 | 多个 HAP 共享较大运行时代码/资源 | 增加依赖包安装/升级一致性、资源归属和发行测试 | 当前单 HAP 无明确收益，暂不引入 |
| Feature HAP | 独立能力、按业务场景分发 | 各自 UIAbility；现有 Router 页面路径不能直接跨 HAP；需要显式启动、状态交接和未安装处理 | 暂不拆编辑/恢复/设置页面 |
| 多设备 target / 定制入口 | 后续桌面独有系统能力、权限或显著不同的设备配置 | 设备分发规则、包身份、签名、资源/源码集和升级矩阵需要独立验收 | 优先评估同模块不同 target；不是另建不相干包名 |

当前单模块、`useNormalizedOHMUrl: true`、无自研 Native `.so`；依赖与资源尚未经过跨模块运行验证。首次拆包必须检查：

1. 保持现有 bundleName、签名身份、版本升级关系；不以卸载重装验证数据兼容。最低 API 22 是兼容目标，当前编译器是 API 26，二者不能混淆。
2. `filesDir/library`、`drafts`、附件、回收站与 preferences 都依赖上下文；改变模块或上下文归属前验证目录迁移，确保升级后仍能恢复旧草稿、打开旧最近项。
3. `$rawfile('web/...')`、HTML 相对 bundle 路径、预览附件资源映射必须一起检查。抽走 JS 文件后，能编译不代表 Web 能加载。
4. 普通相对 import 必须改为模块导出与 oh-package 依赖；保持统一 useNormalizedOHMUrl。不要保留跨模块深层相对路径。
5. FileOpen skills、URI 授权与保存必须在新 Ability 生命周期实测；跨 Ability 不能只传字符串并假设仍有写权限。
6. 同一文档多会话同时保存、后台检查点和旧 bridge 回调不得互相覆盖；不能把 AppStorage 或模块全局变量当跨进程持久共享状态。
7. 设备 target 的能力、权限和 deviceTypes 必须匹配；若将来加 C++，另补 arm64/x86_64 等实际发布 ABI 与依赖 `.so` 检查。
8. entry 目前 `deliveryWithInstall:false`、`installationFree:false`；本轮未改分发配置，单 HAP 调试成功不等于 App Pack 商店分发通过。新增 feature 或 HSP 后须验证 pack.info、依赖安装、首次启动、缺包及升级失败恢复；发布前还需正式签名与混淆回归。

最低升级验收矩阵：现有单包安装且含文档/附件/未保存草稿 → 不卸载覆盖升级 → 最近记录/草稿恢复/外部 URI 再授权/保存与导出 → 缺包或加载失败时正文与草稿可保留 → 使用后续更高版本验证修复路径。旧版设备与新 SDK 各至少一台，手机、平板、2in1 各有实际运行记录后再宣称全端可用。

## 官方依据

- [应用程序包术语](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/application-package-glossary)：HAR 编译态复用、HSP 运行时复用、多包复制差异。
- [跨 HAP 包页面跳转方案](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-package-structure-76)：Router/Navigation 不能跳到其他 HAP 页面，需 startAbility；共享页面优先考虑 HAR/HSP。
- [定制多目标与多产物](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-hmos-customized-multi-targets-and-products-guides)：target 可定制设备、源码、资源、ABI 和分发规则。
- [工程级 build-profile](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-hmos-hvigor-build-profile-app)：统一规范 OHM URL 与跨模块导入约束。

API 门控起始版本同时以本机 SDK 声明与实际 ArkTS 编译结果核对；版本判断不替代旧设备验收。
