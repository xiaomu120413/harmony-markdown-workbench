# 拖入类型一致性 ST-DROP-005

REQ-DROP-005：编辑器中图片、TXT、HTML 插入当前文档；Markdown（md/markdown）按用户确认继续单独打开。插入不改变标题或既有正文，不留下 HTML 中间文档，图片支持清单与预览/导出一致。

审计：图片与 TXT 已走附件节点；HTML 已走受限内嵌节点，但先保存资料库中间副本；BMP 在拖入白名单中，却遗漏预览/导出附件白名单。PDF、Word、Excel 等当前未支持，入口应拒绝且保留当前正文，不假装可预览。

设计：复用现有附件复制、HTML 合成与插入；HTML 原始临时副本仅在本次操作期间保留，拖入及选择器两条路径均清理；Markdown 的独立打开路径保留。BMP 补入同一附件校验及 MIME 映射。无新增权限、类或状态字段。

验证（2026-10-21）：

- `node scripts/test/test-host.cjs`：268/268，新增图片全格式复制与 MIME 对应、HTML/HTM 临时附件不生成资料库文档、md/markdown 保持独立文档及 PDF/Office 拒绝；平台 IO mock。
- `node scripts/test/test-file-transactions.cjs`：35 场景。HTML 拖入成功/失败/异步切换均清理原始临时附件、不改变标题或 pendingOpenUri；选择器读取失败和切换会话清理；Markdown 仍设置独立打开目标。
- editor-actions 40 场景、html-embed 13 组、html-resources 10 组通过。
- `hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release`：通过，复用既有调试签名覆盖安装 com.mumark.app。
- MateBook API 26：在已有测试副本中真实拖入 2×2 BMP，正文新增图片引用，原文及 TXT 节点保留，预览图片节点尺寸非零、显示已保存；真实拖入含 CSS 和脚本的 HTML，当前标题不变，生成 HTML 节点并自动保存，预览显示 HTML NODE CHECK 和 STATIC CONTENT，未出现脚本替换的 SCRIPT_RAN。资料库无本次 HTML 中间文档，附件目录也无原始 matrix-20261021.html，只保留合成 HTML。
- 同一设备随后拖入 matrix-20261021.md，标题切换并显示其独立正文，已保存；原测试文档仍包含图片/TXT/HTML 引用，未改外部测试源或删除用户文档。
- 手写文件 500 行门禁、UTF-8、文档链接和差异检查在提交前运行。本轮未重试此前通信失败的 SDK 单测运行器；手机/API 22 平板未做本轮真机回归。JPEG/GIF/WebP 使用宿主类型及资源契约覆盖，不声称本轮逐个真机解码。

本机 build-profile.json5 为用户已有配置，保留且不提交。本轮不新增 PDF/Office 解析或节点能力。
