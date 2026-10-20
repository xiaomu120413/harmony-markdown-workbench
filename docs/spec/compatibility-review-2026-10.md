# 权限与设备兼容复核 ST-COMPAT-001

2026-10-20，基线 58cdda4，Windows / 当前 DevEco SDK。开始时工作区干净，已有提交均在 origin/main。

REQ-COMPAT-001：HTML 补资源仅在支持目录选择的设备提供目录入口；其他设备直接选择图片/CSS 文件，取消不插入半成品。修正旧性能报告中“无权限声明”的过时描述。

设计与实现范围：沿用 EditorDelivery，以 SDK 声明的 SystemCapability.FileManagement.UserFileService.FolderSelection 判断入口；不按手机/平板型号硬编码，不新增状态、封装、权限或分包。ST-COMPAT-001 仅修改此分支、对应两条控制器回归及权限说明。回滚可直接回退提交，不涉及存储格式迁移。

当前仅声明 ohos.permission.FILE_ACCESS_PERSIST，用途为用户选择的单文件重启后继续读写；生产权限审批与签名授权由用户完成，代码声明或验证包成功不等于正式获批。无此能力或权限失败时使用临时授权，重启后可能需重新选择。HTML 同目录资源通过系统选择器临时获取，生成自包含附件，不申请全盘目录、相册、网络、定位、相机或麦克风权限。

申请用途可填写：“用于持久访问用户通过系统文件选择器明确选择的 Markdown、TXT 文档，支持应用重启后从最近文件继续打开、编辑及保存，仅访问用户已授权的单文件。”设备范围与批准结果以华为当前应用后台及正式签名为准。依据：[官方权限列表](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-v5/permissions-for-all-V5)、[fileShare API](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V13/js-apis-fileshare-V13)及本机 SDK @ohos.fileshare.d.ts / @ohos.file.picker.d.ts。

兼容边界：最低 HarmonyOS 6.0.2 / API 22；此前已有 API 26 真实 2in1 和 API 24 手机模拟器 HTML 插入验收，不能据此宣称真实手机、API 22 或全部文件提供方通过。HTML 内容块是木笺扩展图片式引用，其他 Markdown 阅读器不保证直接显示，跨应用交付优先用 HTML 或 ZIP。脚本、网络资源和部分 CSS 导入条件不支持。单 HAP 维持不变；未来仅拆源码文件不改变安装兼容，若改 HSP/HAP 则需单独验证资源路径、模块依赖、签名与历史数据升级。

## 本轮验证

- `node scripts/test-file-transactions.cjs`：21 场景通过，含目录能力存在/缺失时的选择器参数及取消保护；平台接口为 stub。
- `node scripts/test-html-resources.cjs`、`node scripts/test-html-embed.cjs`：各 10 组通过；`node scripts/test-external-access.cjs`：9 场景通过。
- DevEco 内置 JBR：`hvigorw.bat test --mode module -p product=default` 与 `hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release` 均 BUILD SUCCESSFUL；日志保存在忽略目录 build-logs/compat-review-test.log 与 compat-review-release.log。既有弃用 API / ESObject 警告仍在。
- `node scripts/check-source-size.mjs`：128 个手写文件不超过 500 行；`node scripts/check-source-encoding.mjs`、`node scripts/check-docs.mjs`、`git diff --check` 通过。

本轮入口分支依赖系统能力，主机 stub 验证两侧行为不等同于真机验收；仅检查到手机模拟器在线，未重新部署执行设备交互矩阵或正式签名升级。此前设备证据仍仅代表对应版本和场景。
