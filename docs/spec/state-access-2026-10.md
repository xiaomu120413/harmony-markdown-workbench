# 状态精简、外部文件持久授权与设置帮助

## 范围与验收

- REQ-STATE-001：EditorState 只保留展示所需状态；会话、加载正文、版本与缓存移入现有 EditorEnvironment，不新增状态管理框架。
- REQ-STATE-002：删除重复生命周期标记，查找数量和冲突提示从单一来源派生；State 不操作 AppStorage。
- REQ-ACCESS-001：仅对用户已经授权的单文件申请持久访问，重启读取前校验并激活；权限未获批、不支持或授权撤销时保留临时访问与重新选择降级。
- REQ-HELP-001：帮助并入设置的可滚动内容，移除编辑器长文本帮助弹框。
- 所有手写文件不超过 500 行。不得清除生产安装或用户文档。

## 设计与交付单元 ST-STATE-001

沿用 Controller、State、Environment；保存状态只向界面发布一个 SaveState，显示文案和冲突可见性派生。查找列表作为展示源，数量由列表长度派生。

持久授权位于文件基础设施边界，使用当前 SDK 的 fileShare.checkPersistentPermission、persistPermission、activatePermission；只申请读写操作，不申请目录遍历、创建或删除能力。只读授权单独降级，不扩张到父目录。错误记录代码而不记录文件 URI。

声明 ohos.permission.FILE_ACCESS_PERSIST；应用市场/签名权限由用户申请。代码接入不代表生产授权已通过。原文件读写仍走冲突检查，失败不能伪装为已保存。

设置使用现有分组样式展示文件规则、恢复入口与快捷键，不新增帮助路由、ViewModel 或状态容器。

真机发现 CodeMirror basicSetup 的 Ctrl+F 优先于应用快捷键，导致打开第二套查找界面；将应用 keymap 排在 basicSetup 之前，保持帮助说明与实际行为一致。设置返回编辑器时重新应用样式，但保留当前视图。

验证：真实 ArkTS 模块的主机回归、持久授权异常/只读/撤销用例、构建、UTF-8/文档/行数检查，以及已连接 API 22 平板的设置帮助与文件访问验收。生产权限未批造成的未验证项须明确记录。

回滚：整体回退本次提交；已取得的单文件授权不影响文档内容，失败仍可重新选择原文件。

## 验证记录

2026-10-19，Windows、DevEco 内置 JBR 与 API 26 SDK，最低兼容 API 22。工作区初始干净。

| 验证命令 | 结果 |
|---|---|
| `node scripts/test-host.cjs` | 234/234，通过真实领域逻辑与模拟平台 IO |
| `node scripts/test-editor-actions.cjs` | 23 组，含派生状态、过期快照、旧页面回调与设置返回保留视图 |
| `node scripts/test-file-transactions.cjs` | 14 组，另存切换、导出、取消/失败与后续保存 |
| `node scripts/test-external-access.cjs` | 9 组，首次保留、重启激活、只读降级、拒绝、撤销、临时读取与禁止无权写回；系统授权边界为 mock |
| `node scripts/test-page-viewmodels.cjs` | 7 组通过 |
| `node scripts/test-window-viewport.cjs` | 8 组通过 |
| `node web-tools/build-web.js` | 成功，重新生成并提交 editor bundle |
| `hvigorw.bat test --mode module -p product=default` | BUILD SUCCESSFUL，无测试断言错误；日志 `build-logs/state-test.log` |
| `hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release` | BUILD SUCCESSFUL，日志 `build-logs/state-release.log`；仍有既存弃用/ESObject 警告 |
| `node scripts/check-source-size.mjs` | 126 个手写源文件/测试/脚本均不超过 500 行 |
| `node scripts/check-source-encoding.mjs`、`node scripts/check-docs.mjs`、`git diff --check` | 通过；中文回读正常 |

EditorState 的存储字段从 51 减到 35；13 个非展示字段移至现有 Environment，删除 pageActive，matchCount 和 conflictVisible 改为 getter；saveLabel 从 loadState 与单一 SaveState 派生。没有新增刷新计数、状态管理库或帮助 ViewModel。

### API 22 平板实测

设备 PCE-W30 / MatePad Pro，OpenHarmony 6.0.2.130、2880×1920。仅升级验证包 `com.markdownworkbench.validation`，未改生产安装、未清数据。

- 设置帮助使用分组文字与快捷键行，滚动到底可完整阅读；编辑器入口改为“设置”，没有长文本帮助弹框。
- 真机查找 `Token` 显示 1/2；继续向正文追加 Token 后直接变为 1/3，证明 getter 随列表变化更新。
- 修复前 Ctrl+F 打开 CodeMirror 内置英文搜索；最终验证包 Ctrl+F 打开木笺原生查找栏。
- 新建测试正文后另存为个人文档目录的 `MuMark-StateAccess-1621.md`；16:22:16 日志 `persistent access active, mode=3`，PID 14367。
- 升级并重新启动验证应用（PID 19707），从最近列表直接打开同一外部文件，16:22:45 激活读写授权，加载 45 字符，无需再次选文件。
- 在该外部文件追加 ` RestartWrite` 并保存；再次升级启动（最终验证包 PID 21673），16:25:25 激活读写授权，16:25:26 加载 58 字符，正文包含新增标记。原位写回跨进程复读成功。
- 从编辑器进入设置，切换深色后返回，编辑器与文字立即变深色；之后恢复浅色。
- [设置帮助](../ux/state-access/settings-help.jpg)、[重启后复读](../ux/state-access/reopened-write.jpg)、[设置返回生效](../ux/state-access/settings-return-dark.jpg)。截图仅等比缩小，来源见同目录 captures.json。

未验证：生产包正式权限审核/发布签名、物理设备重启、真实手机、2in1、云盘提供方、系统设置撤销授权与只读文件。这些异常已做 mock，不等于真机验收。当前实测为应用进程重启；生产授权仍由用户申请。

### 权限申请

仅声明 `ohos.permission.FILE_ACCESS_PERSIST`，不申请全盘目录、相册、读取剪贴板、定位、相机或麦克风权限。拖入只导入副本，不保留源文件授权；导出副本也不自动保留授权，只有打开的原文件和另存后的当前文件进入持久授权链路。

申请用途：用于持久访问用户通过系统文件选择器明确选择的 Markdown、TXT 文档，支持应用重启后从最近文件继续打开、编辑及保存，仅访问用户已授权的单文件。

依据：[官方权限列表](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-v5/permissions-for-all-V5)、[fileShare API](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V13/js-apis-fileshare-V13)，并已核对本机 SDK `@ohos.fileshare.d.ts` 的 API 11/12 接口和 FolderAuthorization 能力声明。官方权限列表要求继续按受限权限方式申请；代码和验证签名上的成功不代表生产审核通过。
