# 文档操作入口验收

2026-10-19；初始工作区干净，基线 4c0756f。[需求与设计](document-actions-2026-10.md)。

## 环境与方法

Windows PowerShell，DevEco SDK API 26；HUAWEI HAD-W32 / OpenHarmony 7.0.0.106，设备 3QC0124C11000711。通过独立验证包 com.markdownworkbench.validation 升级安装，不清空原包或验证包内容。生产配置仍为 com.markdownworkbench.app。

使用 HarmonyOS connector 的 install_app、run_app、get_ui_tree、screenshot、click、press_key、swipe；原生鼠标缩放使用 `hdc shell uinput -M -g 起点X 起点Y 终点X 终点Y 1500`。所有下述截图位于本机 `C:/Users/mu/harmonyos-screenshots/`，均已打开检查。

## 需求验收

| 需求 | 结果与证据 |
|---|---|
| FR-ACTIONS-001 | 2090×1394px 宽窗：轻量文件夹图标 + 文档入口，首层六项，导出副本下展示 ZIP/HTML/Markdown 三项及用途。截图 101759、102455；后者 UI 树也确认三级格式标签存在 |
| FR-ACTIONS-002 | 实际缩至 873×1304px、723×994px，触发 <600vp 分支，标题栏包含文档名/保存状态/保存/省略号，编辑/预览/大纲/查找另行显示，侧栏隐藏。底部原生面板展示文档位置和状态，导出二级可返回。截图 101923、101946、102219、102322 |
| FR-ACTIONS-003 | 发现并修复系统三键与窄窗入口重叠；通过实际三键矩形避让。长名称在标题栏省略、面板有完整可用展示；短窗可滚动到复制/保存位置/帮助（102257）；导出短列表改为靠顶（102322）。窄窗从面板打开系统选择器，取消返回仍为 EditorPage、117 字正文及测试标记保留（102014、102017）。大纲面板展示 `# MuMark safety`。系统 Back 关闭面板后仍在编辑页；面板打开时拉宽自动关闭，正文仍 117 字。深色时原生系统三键曾为黑色，补齐应用 ColorMode 同步后变为可见浅色（102610、102618）。验收后恢复原浅色设置及宽窗 |
| FR-ACTIONS-004 | module.json5 无变更，零新增权限；当前链路继续使用系统选择器及系统文件交付，不申请公共目录权限 |

截图文件名均为 `screenshot_20261019_HHMMSS.jpeg`。101251 为开始时首页；101816、101822 是修复系统三键避让前的中间状态，不代表最终效果。102618 为最终代码安装后的深色窄窗面板。

## 命令与结果

在仓库根目录执行；构建 Java 使用 DevEco 的 jbr。

| 命令 | 结果 |
|---|---|
| `node scripts/test-host.cjs` | 228/228 通过；平台 IO 使用 mock，不替代真机授权验收 |
| `node scripts/check-docs.mjs` | 30 个 Markdown 文件 UTF-8 与本地链接通过 |
| `hvigorw.bat test --mode module -p product=default` | BUILD SUCCESSFUL，exit 0 |
| `hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release` | 最终源码 BUILD SUCCESSFUL，exit 0 |
| `powershell -ExecutionPolicy Bypass -File build-logs/rebuild-validation.ps1` | Debug 构建和复用本地验证证书签名成功，安装运行成功；临时包名修改已还原 |
| `git diff --check` | 通过 |

本轮以原生交互验收覆盖展示与平台主题行为，不为样式和平台 API 调用编写镜像测试。宿主日志 `build-logs/actions-host.log`、`actions-unit.log`、`actions-release.log` 为忽略产物，不入库。

## 未验证与边界

- 当前只有 2in1 真机，窄窗触发 phone 分支不等于手机实机通过。手机键盘、旋转、安全区和不同系统版本仍需手机验收；本轮未声称三端全量完成。
- 本轮不重复全部真实授权/拖入异常路径，已有证据见[上一轮入口验收](file-intake-verification.md)；未变更这些服务。
- 目录工作区、兄弟图片自动读取不在当前能力中；不以新增 3D 公共目录权限掩盖单文件授权边界。
- 生产签名覆盖原安装的验收仍受原签名不可用限制；本轮测试使用独立验证包，Release 构建不等于正式包覆盖安装已通过。
