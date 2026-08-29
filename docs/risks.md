# 风险清单

> 依 SDD 17 章与阶段 1 输出要求。概率/影响：高 / 中 / 低。M0-01 实测新增风险编号 R-01 起。
> 计划：SDD 原风险 | 实测风险。最后更新：2026-08-29（M0-01）。

## SDD 已识别风险（转录）

| 风险 | 概率 | 影响 | 缓解措施 | 最晚验证 |
|---|---:|---:|---|---|
| 外部 URI 无法长期授权 | 高 | 高 | 临时访问标识、重新定位、内部副本显式选择 | M0-02 |
| ArkWeb 中文输入兼容问题 | 中 | 高 | 真机 IME 尖峰、固定编辑器版本、组合输入测试 | M0-03 |
| 外部文件无法原子替换 | 高 | 高 | 草稿先落盘、冲突检测、失败保留正文 | M0-04 |
| 大文档渲染卡顿 | 中 | 中高 | 防抖、Worker、关闭实时预览降级 | M0-03/M6-02 |
| Web 与原生状态不一致 | 中 | 高 | 单一正文真源、版本化 Bridge、请求式快照 | M2-02 |
| Markdown HTML 注入 | 中 | 高 | 默认禁 HTML 或严格 Sanitizer、离线 CSP | M3-01 |
| 图片相对路径受 URI 限制 | 高 | 中 | V0.1 明确限制，V0.2 附件目录与导出包 | V0.2 前 |
| 依赖许可证不兼容 | 低中 | 高 | 引入前审核、NOTICE、优先 MIT/BSD/Apache | 每次引入 |

## M0-01 实测风险（新增）

| ID | 风险 | 概率 | 影响 | 缓解 / 现状 | 截止 |
|---|---|---|---|---|---|
| R-01 | 工程内复制官方 `hvigorw.js` 会因路径推导错误导致构建失败（`resolve(__dirname,"..")` 机制） | 已发生 | 高 | 已解决：wrapper 改为转发到官方位置（ADR-006）；README 记录环境要求 | 已闭环 |
| R-02 | 根 `build/` 目录被 hvigor 管理（启动时清理），存放自定义文件会被删除 | 已发生 | 中 | 已解决：日志改用 `build-logs/`；脚本与 README 说明 | 已闭环 |
| R-03 | hvigor 项目缓存目录（`~/.hvigor/project_caches`）损坏/不完整时构建报 00308003 | 已发生 | 中 | 已解决（根因为 R-01）；`hvigorw prune` 或删除缓存目录可恢复 | 已闭环 |
| R-04 | 本机 Node v25 与 DevEco 工具链兼容性未全面验证（构建已验证） | 低 | 低 | DevEco 官方要求建议 Node LTS；持续验证中 | 每次构建 |
| R-05 | 命令行无 Code Linter / 格式化工具（DevEco IDE 内置） | 确定 | 中 | IDE 执行 lint；编译严格模式兜底；M0-01 记录为已知限制 | M6-03 |
| R-06 | GitHub Actions（hosted）无 HarmonyOS SDK，云端 CI 不可用 | 高 | 中 | 自托管 runner 预留；clean-build 脚本本地等价（ADR-008） | M0-02 前评估 |
| R-07 | hypium 用例失败时 hvigor `test` 任务仍返回成功（断言失败仅打 ERROR 日志，无结构化结果文件） | 已发生 | 高 | clean-build 脚本 grep 日志 ERROR 行作为门禁；文档注明；后续任务评估自定义 runner/退出码 | M2 起持续 |
| R-08 | 构建用 SDK 为 API 26 **Beta1**（HarmonyOS 6.6.0 Beta），正式发布存在工具链变更风险 | 中 | 中 | 正式发布前复核发布版 DevEco/SDK；构建产物仅用于开发验证 | M6-04 |
| R-09 | app 图标为脚本生成占位（渐变+M），非正式设计 | 确定 | 低 | M6 前输出正式图标资源 | M6-03 |
| R-10 | API 26 Beta（26.0.0.23）`uriPermissionManager` 类型为空，persistPermission 编译期不可调用；模块增强在 ArkTS 下不生效 | 已发生 | 高 | 真机实测重启后 URI 失效（13900001）证实持久化必要性；V0.1 按"临时访问+重新定位"降级交付（ADR-009 草案）；正式 SDK 复核后关闭 | 正式 SDK 发布后 |
| R-11 | 本机设备（MateBook Pro，OpenHarmony 7.0 华为定制镜像）信任库不含 OpenHarmony Profile CA，第三方调试签名安装被拒（9568329） | ✅ **已解决** | — | 1) 官方 CA 体系签名（sign-local.sh：app/profile 证书由 Application CA 签发，subject 按信任源 DN）；2) Profile CA 补入设备 `trusted_root_ca.json`（/system overlay 可写）；3) profile 含 validity；4) deliveryWithInstall=false。**真机安装成功并运行** | 已闭环（2026-08-29） |
| R-12 | 本镜像文件选择器（filemanager picker）UI 自动化"打开"按钮事件注入不生效（真实用户手动操作正常——有成功选择记录）；"最近"索引不收录新 push 文件 | 确定 | 低 | 自动化验证受限项如实标注；人工/标准镜像复测；选择器打开与选中已验证 | M0-02 复核 |
| R-13 | 设备重启后进入锁屏（需用户密码），`aa start` 报 10106102；无命令行解锁途径 | 发生中 | 中 | M0-03 剩余 UI 必测项待设备解锁后执行（步骤见 editor-runtime.md 第 2 节）；不阻塞纯逻辑/单测/构建类工作 | 用户解锁后 |
| R-14 | 锁屏显示方案不可行：`setShowOnLockScreen` 为 FA 模型废弃接口（deprecated since 9），指向的 `WindowStage#setShowOnLockScreen` 在 API 26 Beta 无类型声明 | 确认 | 低 | 放弃该路径；锁屏解除仅能由用户输入密码（安全机制） | 已闭环 |