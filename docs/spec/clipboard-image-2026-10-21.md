# 系统图片粘贴 ST-PASTE-001

REQ-PASTE-001：用户通过系统粘贴交付图片时，在当前文档插入图片附件引用；保留正文和标题，可自动保存、预览和导出。不新增 READ_PASTEBOARD，不主动监听或读取剪贴板。

设计：只处理编辑器收到的真实 paste 事件中的 image File，文字粘贴维持默认。复用原桥、附件目录和保存流程。一次一张、20 MB，支持 PNG/JPEG/GIF/WebP/BMP；校验传输长度、图片头及路径。插入时校验粘贴开始时的会话、版本、选区，变化则提示重试并清理本次附件；不留下半成品正文。失败和不支持格式有提示，不回退为主动读取权限。

依据：系统 paste 事件只交付当前用户粘贴的数据；未使用 navigator.clipboard、pasteboard.getData 或新增权限。若设备 ArkWeb 没有交付图片 File，只能如实记录设备限制，不以模拟事件代替真机验收。

验证（2026-10-21）：

- `node scripts/test/test-clipboard-image.cjs`：系统事件/FileReader 边界 mock，执行真实 Web 图片处理器、InternalFileSource 和 EditorDelivery。覆盖普通文字保留默认、伪造事件/只读拒绝、图片交付及原选区、SVG 拒绝、20 MB 限额、多图片、读取失败、格式头不符、空数据、附件原始字节、成功写回、版本变化/桥失败清理、旧会话/忙碌/非法选区拒绝及无 READ_PASTEBOARD 声明。已接入 CI。
- `test-host.cjs`：268/268；`test-file-transactions.cjs`：35；`test-editor-actions.cjs`：40；`test-html-embed.cjs`：13 组通过。
- `node web-tools/build-web.js` 重建编辑器 bundle；`hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release`：通过，复用已有调试签名覆盖安装，不新增包、证书或权限。
- MateBook Pro 3QC0124C11000711 / API 26：系统图片预览器打开测试 BMP，Ctrl+C；切回木笺测试文档 Ctrl+V，提示已粘贴图片，正文保留且新增应用附件引用，自动保存成功。Ctrl+Z 一次移除插图，Ctrl+Shift+Z 一次恢复。普通文字复制/粘贴仍插入文本，不生成图片附件。
- 同一设备再从系统图片预览器复制 PNG，Ctrl+V 生成独立 PNG 附件。预览两张图的节点尺寸分别为非零的 4×5 和 3×3，标题及原文保留、已保存。落盘 BMP/PNG 回读 SHA-256 与复制源逐一相同。测试仅在此前创建的 matrix-20261021.md 副本中操作，未修改外部原文件或删除现有文档。
- 自动化点击曾把光标落在已有图片链接中间，插入按实际选区执行；撤销后移至行末重新粘贴，最终两个引用独立完整。未将这种光标定位当作传输失败，也未宣称执行了未发生的选区替换实机验证。
- `check-source-size.mjs`：130 个手写文件均不超过 500 行；`check-source-encoding.mjs`：242 个文本；`check-docs.mjs`：63 个 Markdown 与链接通过；`git diff --check` 通过。
- 本轮真机验收为 Ctrl+V 路径；手机/平板、系统右键/长按粘贴菜单、JPEG/GIF/WebP 逐格式真机粘贴未验收。不以伪造 ClipboardEvent 替代上述真机结果。此前 SDK 单测运行器本机通信异常，本轮未重试，宿主 mock 与设备结果分别列出。

用户已有 build-profile.json5 本机签名改动保留且不提交。无 READ_PASTEBOARD 新增声明或主动读取接口。

交付：代码 `44c2b86` 已推送。最终构建再覆盖安装后，测试文档中的 BMP/PNG 引用及“已保存”状态保留。独立签名目录执行 `assembleApp --mode project -p product=default -p buildMode=release --no-daemon`，44 个任务通过；SDK verify-app 验签和摘要成功，提取 Profile 与既有 MumarkRelease.p7b 一致。dist 的正式 signed APP、signed HAP、unsigned APP 已更新；signed APP SHA-256 为 `7e9002a65c559785fb27f8e180f47caeb733d1c389ee0ba7e08ac567d9feb5ad`。真机覆盖包使用既有调试签名，发布产物使用既有正式签名，未混称或新增证书。
