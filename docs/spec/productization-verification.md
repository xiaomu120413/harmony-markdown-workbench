# 木笺 MuMark 产品化验证记录

本页保留首轮验收事实。原先待验收的真实文件管理器授权入口，后续已完成冷/热启动和保存验证，见[后续验收](file-intake-verification.md)；拖入副本与菜单改进也以该记录为准。

日期：2026-10-19。任务：TASK-SAFE-001 / TASK-DELIVER-001 / TASK-BRAND-001。
范围与验收见 [增量规格](productization-2026-10.md)。

初始工作区：`git status --short` 为空。环境：Windows PowerShell、DevEco Studio、本机 SDK；设备 HAD-W32 / OpenHarmony 7.0.0.106 / API 26。
本页只记录实际执行结果，未执行项保留为未验证。

## 执行记录

### 自动化与构建

工作目录均为仓库根目录。构建前设置 `JAVA_HOME=C:\Program Files\Huawei\DevEco Studio\jbr`，并将其 `bin` 加入 PATH。

| 命令 | 实际结果 |
|---|---|
| `npm.cmd ci --no-audit --no-fund`（web-tools） | 成功，依赖锁文件未变 |
| `node web-tools/build-web.js` | 成功，编辑器与预览 bundle 已同步提交 |
| `node scripts/test/test-host.cjs` | 220/220 通过；执行实际领域/服务代码，平台 IO 使用宿主机文件及故障注入替身 |
| `node scripts/check/check-docs.mjs` | 26 个 Markdown 文件通过 UTF-8 和本地链接检查 |
| `hvigorw.bat test --mode module -p product=default` | BUILD SUCCESSFUL，Hypium 测试构建/执行完成 |
| `hvigorw.bat assembleHap --mode module -p product=default` | Debug HAP 构建通过 |
| `hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release` | Release HAP 构建通过 |
| `git diff --check` | 通过 |

宿主机用例覆盖：关闭原文件自动保存时独立检查点、检查点失败阻断覆盖、保存期间新编辑、延迟通知、旧会话拒绝、快照失败、串行检查点收敛、短读短写、多字节字符、fsync 失败保留旧文件、目标写失败恢复旧内容、选择器取消、用户修改目标名称、缺失/越界附件、引用式图片解析、代码块排除及 HTML 图片嵌入。平台替身不能证明设备提供方 IO 的全部行为。

### 真机验收

设备：HUAWEI MateBook Pro HAD-W32，OpenHarmony 7.0.0.106，API 26。用户明确授权继续操作设备。
现有正式包 `com.markdownworkbench.app` 的安装签名与本地开发证书不同，直接覆盖安装报签名不一致。未卸载、清空或迁移原应用数据；本次使用隔离验证包 `com.markdownworkbench.validation`。最终仓库和正式 HAP 仍保留原包名。

| 场景 | 操作与证据 | 结论 |
|---|---|---|
| 自动保存关闭仍可恢复 | 关闭自动保存，新文档输入 `# MuMark safety` 和中文。检查沙箱 drafts JSON 含完整正文，且尚无 library 原文件；`hdc shell aa force-stop com.markdownworkbench.validation` 后重启，首页显示找回 1 份内容，恢复页预览正确 | 通过 |
| 图文 ZIP | 内部文档引用 `attachments/test.png`（77 字节 PNG），通过系统选择器导出 `mumark-validation-20261019.zip`，用 hdc 取回并由 Python zipfile 检查 | 通过：仅 `document.md`、`attachments/test.png`；CRC 无错，正文含中文/emoji，图片字节一致 |
| 独立 HTML | 同一图文文档导出 `delivery.html`，取回并检查正文及 data URI | 通过：中文正文存在，base64 解码与原 PNG 字节一致，无私有目录图片依赖 |
| 另存为后继续保存 | 将内部 `MuMark safety.md` 另存为 `mumark-save-as-20261019.md`，继续输入 `SAVE_AS_FOLLOWUP_20261019` 并 Ctrl+S，再取回两端文件 | 通过：新目标含后续标记；原内部文件前后 SHA-256 均为 `0f9806159e3278451c6da931f6c77dfbc1fb709e813274e137dbeb80f07aba57` |
| 取消交付 | 含图片的纯 Markdown 提示取消后保留原编辑目标；选择器取消路径另有宿主机用例 | 已覆盖提示取消；未穷举全部系统选择器取消方式 |
| 外部打开入口 | 用 `aa start` 的 viewData/URI/MIME 调度验证；安装配置包含 FileOpen 和 Markdown/plain text 类型；无临时 URI 授权时读取明确失败 | 分发与拒绝路径通过；文件管理器“打开方式”实际授权成功链路未完成 |
| 品牌与启动 | 桌面显示木笺名称及蓝青渐变、白纸薄荷笔图标；更新后的验证包成功覆盖安装、启动 | 通过；原正式应用仍保留 |
| 最终图片预览回归 | 最终验证包打开 delivery.md 并切换预览，正文及 8×8 蓝色 PNG 均正常显示；截图 `screenshot_20261019_093544.jpeg` | 通过；宿主机同时覆盖带空格尖括号路径的解析与资源替换 |

正文经编辑器规范化为 LF，因此 ZIP 对比的是编辑器快照文本，不宣称与导入前 CRLF 文件逐字节相同。
实际选择器 URI 为 `file://docs/storage/Users/currentUser/...`；手工构造 URI 或启动命令不等于获得系统授权。
验收中发现并修复：ArkUI 私有 getter 导致侧栏渲染异常、Web keymap 初始化错误、选择器改名后标题仍用建议名称、切换文档沿用前一文档撤销历史。最终构建包含这些修复。
冲突面板的“另存副本”也统一进入可靠另存链，仅在写入成功后切换目标；该入口已通过构建，未另行制造真机冲突验证。最终 Release 产物核对为 `com.markdownworkbench.app` / 1.1.0 / `debug=false`。

### 验收结论与限制

- FR-SAFE-001～003：实现完成，自动化及上述真机恢复场景通过。尚未测试真实断电、磁盘耗尽、所有文件提供方断连；强杀前尚未到达原生层/落盘的输入仍可能丢失。
- FR-DELIVER-001～002：实现完成，另存为继续保存、ZIP、内嵌图片 HTML 真机通过。外部 URI 无通用原子替换保证；已有目标备份超过 32 MiB 时会拒绝覆盖。未获得目录授权的外部相对图片会阻止图文交付，远程图片仍需要网络。
- FR-DELIVER-003：实现完成，真实文件管理器授予 URI 权限后的完整“打开方式”流程待验收；无授权失败不会伪装成功。
- FR-BRAND-001：名称、版本 1.1.0、资源、矢量源和生成脚本已完成；正式包名不变。正式覆盖升级仍需原签名材料，本次隔离装机不证明正式升级兼容性。
- 未进行手机/平板全矩阵、性能压测、真实断电和完整系统文件提供方兼容性测试。SDK 输出仍有现存 ESObject/弃用 API 警告，构建通过不代表消除这些技术债。

本地原始日志、导出样本位于忽略目录 `build-logs/`，签名材料及隔离签名 HAP 在仓库外，不提交证书、私钥或设备导出内容。
