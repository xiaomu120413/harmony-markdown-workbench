# 拖入 TXT 与图片 ST-DROP-002

REQ-DROP-001：TXT 导入须正常创建私有副本；写入失败记录真实原因，不能一律提示空间不足。
REQ-DROP-002：编辑器拖入 PNG/JPEG/GIF/WebP/BMP 时复制图片后在光标处插入；首页及 HTML 预览页拖入图片时创建带附件的新文档。切换会话或插入失败须清理本次附件，不修改外部原文件。

设计：复用现有异步拖放、附件复制和 EditorDelivery 插入流程，不新增状态层。兼容文件存在性检查抛出 13900002 的平台行为；其他访问错误继续抛出。导入名称为 UTF-8 文件名预留长度预算。

定位：用户确认完整提示为“导入副本保存失败，请检查可用空间后重试”。这是旧的通用写入错误提示，不能据此判定磁盘已满。当前 SDK 的 accessSync 声明允许抛出 13900002；旧代码在新文件检查及原子改名后的临时文件清理中均未兼容此异常。图片则被拖入格式白名单拒绝。修复存在性检查并显示实际写入错误；不增加权限或签名凭证。

验证（2026-10-20）：

- `node scripts/test/test-host.cjs`：262/262，含不存在抛异常、权限拒绝不能冒充不存在、图片字节与包装文档、长中文文件名；平台 IO mock。
- `node scripts/test/test-file-transactions.cjs`：27 场景，新增图片插入、异步切换会话及插入失败清理；平台选择器 mock。
- `node scripts/test/test-editor-actions.cjs`：40 场景；external-access 9、page-viewmodels 7、window-viewport 8、html-preview 8 组、html-resources 10 组、html-embed 13 组全部通过。
- `hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release`：构建通过，复用用户现有调试签名材料用于覆盖安装，不把调试签名称作发布签名。
- MateBook Pro（3QC0124C11000711，API 26）：覆盖安装 com.mumark.app 成功。文件管理器桌面真实拖入 TXT，正文与 CRLF 副本正确、显示已保存；继续拖入 PNG，当前正文插入附件引用并自动保存；重复拖图生成 `(2)` 附件；返回首页拖图新建 Markdown，预览出现正确尺寸的原生 Web 图片节点。原文档仍在，未卸载或新增第二个包。测试 TXT/PNG 原文件回读 SHA-256 与导入前一致。
- 本轮真机证明修复后的流程可用；未在设备上回装旧版重现 accessSync 抛错，因此不把该平台行为认定为用户设备上唯一的旧版失败原因。
- `hvigorw.bat test --mode module -p product=default`：ArkTS 单测编译完成，Windows 本机运行器停在 Windows_NT，coverage.log 出现 LocalSocket WriteFile failed: 6，数分钟未生成新结果，已终止本次运行。原 test_result.txt 为此前 19:36 的 205 条结果，未计入本轮通过数。
- 手机、API 22 平板本轮未做真实拖放回归；当前平板未连接。照片格式仅接受 PNG/JPEG/GIF/WebP/BMP，SVG 不在白名单，图片上限沿用现有 20 MB。
- `node scripts/check/check-source-size.mjs`：128 个手写源码/测试/脚本符合 500 行上限；`check-source-encoding.mjs` 的 236 个文本文件、`check-docs.mjs` 的 59 个 Markdown 及 `git diff --check` 通过。

原有 build-profile.json5 是用户本机签名配置改动，保留且不提交。发布签名产物使用既有正式签名材料在独立交付目录构建，不新建证书。

正式交付：代码提交 `38cd198` 在 `../local-sign/mumark-release-38cd198-standard` 执行 `hvigorw.bat assembleApp --mode project -p product=default -p buildMode=release --no-daemon`，44 个任务通过（含 SignApp）。SDK `hap-sign-tool.jar verify-app` 验证 APP 摘要及签名成功，提取 Profile 与既有 MumarkRelease.p7b 的 SHA-256 一致。更新忽略目录下的 `dist/mumark-1.0.0-release-signed.app` 和 `dist/mumark-1.0.0-latest-release-signed.hap`，APP SHA-256 为 `bd7913bf913b523c3d5ac968f16b6c55468a4a7d728f4e37d98fec3483a3fc6a`。此正式包用于发布交付；真机验收使用前述既有调试签名覆盖包，两者不混称。
