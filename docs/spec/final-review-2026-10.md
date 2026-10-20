# 推送前整体复查

2026-10-19，TASK-REVIEW-001，基线 542cc64，工作区干净。承接[文档操作](document-actions-2026-10.md) FR-ACTIONS-002/003 与[控件一致性](control-system-2026-10.md) FR-CONTROLS-004。

## 发现、要求与修正

- FR-REVIEW-001：大纲快捷键与按钮在窄窗必须进入同一底部面板，重复触发可关闭，不能挤出 200vp 的桌面侧栏。复查发现桥接命令仍调用旧 toggleOutline；把断点选择收敛到该入口，同时在内联大纲显示处限制非 phone。宽窗仍用原有侧栏。
- FR-REVIEW-002：帮助文本必须实际分行。修正数组 join 的字面反斜杠换行，保留现有操作说明。

单一任务 TASK-REVIEW-001 修改 EditorPage 与行为回归；使用 ArkTS 是因为属于 ArkUI 状态与弹窗。无权限、包结构、文档格式或持久化变化。可按提交回退。

## 整体复查范围

检查首页/编辑/设置/恢复的共享控件、宽窄断点、菜单及快捷键入口；对照既有真实授权、保存恢复、拖入与交付记录。检查 tracked 文件不含签名密钥、HAP 或日志。远端 origin 为用户项目 GitHub 仓库，main 原有 6 个本次系列未推送提交；普通 fetch/push，不改写历史。

## 验证记录

环境：Windows PowerShell、DevEco JBR、当前 API 26 SDK。

| 命令 | 结果 |
|---|---|
| `node scripts/test/test-editor-actions.cjs` | 4 个场景通过：宽窗大纲开关、窄窗大纲开关、其他面板切换到大纲、帮助实际换行 |
| `node scripts/test/test-host.cjs` | 228/228 通过；平台 IO 使用 mock |
| `hvigorw.bat test --mode module -p product=default` | BUILD SUCCESSFUL，exit 0 |
| `hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release` | BUILD SUCCESSFUL，exit 0 |
| `node scripts/check/check-docs.mjs` | 33 个 Markdown 文件 UTF-8 和本地链接检查通过 |
| `git diff --check` | 通过 |
| tracked 文件检查 | 未追踪签名密钥、HAP、日志和本地签名目录；本次无权限、包结构变更 |

回归脚本抽取当前页面真实的非 UI 方法后执行，以最小状态/弹窗 stub 验证分发与换行，不复制方法实现，也不声称验证了 ArkUI 渲染。构建日志为被忽略的 `build-logs/review-*.log`。

当前只有 2in1；设备已有其他应用并行操作，本轮不抢占前台重跑真机。手机、读屏、完整键盘遍历及正式签名覆盖的限制沿用[全局验收](control-system-verification.md)。本次快捷键与帮助修正未部署重验，交付结论为代码行为回归与构建通过，不能写成手机/真机快捷键通过。
