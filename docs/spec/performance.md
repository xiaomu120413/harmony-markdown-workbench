# 性能与质量报告（M6）

## 设备与构建

- 设备：HUAWEI MateBook Pro（HAD-W32），OpenHarmony 7.0.0.28（API 26），3120×2080。
- 构建：Debug（hvigor assembleHap，product=default），本地 CA 签名（sign-local.sh）。
- 测量通道：页面内 `Date.now()` 计时（毫秒级，由 hilog 时间戳佐证）+ hilog 进程时间戳。

## M6-01 响应式（窄窗布局）

- 修复：EditorPage 标题栏/快捷栏/冲突条与 HomePage 按钮区由固定 Row 改为 `Flex(wrap)`；
  SpikePreviewPage 按钮行同样处理（实测 ⑤⑥ 按钮在 742vp 窗口被挤出后修复）。
- 真机复测（742vp 自由窗口）：保存按钮此前不可见 → 现在可见可点（日志 `[保存] 无修改` 确认事件绑定）；
  HomePage 新建文档/打开文件/刷新/设置在 681vp 内容区全部可见。
- 剩余：横屏/分屏布局未逐形态复测（记录为建议人工补充项）。

## M6-02 性能样本（SDD 6.1）

| 样本 | 内容 | 实测 | 验收 | 结论 |
|---|---|---|---|---|
| S1 | 10 KB 普通文档 | 打开至可编辑 **582–601ms**（读盘+JSON 注入+CM dispatch）；10KB 注入 59ms | 冷启动打开 P95 ≤ 1.5s | ✅ |
| S1 冷启动 | 进程创建→HomePage 交互 | **71ms**（onCreate→HomePage loaded，11:20:24.158→.229） | — | ✅（+打开 601ms ≈ 672ms 全链） |
| S2 | 1 MB（500 标题 + 100 代码块） | **注入 57ms**；**首次预览 49ms** | 打开 ≤2.5s；预览 ≤800ms | ✅ |
| S2 输入 | 连续输入 60s P95 ≤ 50ms | 命令级往返样本（注入吞吐 57ms 反映 dispatch 能力；逐键帧率无专用工具） | — | ⚠️ 降级记录：需逐键测量工具补测 |
| S3 | 5 MB 纯文本/Markdown | **注入 116ms，进程存活**（打开不崩溃）；搜索/保存路径已由 M3-04/M4-01 真机验证 | 可打开/搜索/保存不崩溃 | ✅ |
| S4 | 1 MB + 100 本地图片引用 | **预览渲染 30ms，不崩溃** | 不崩溃 | ✅ |

- 打开/注入/渲染样本各 1 次 + 交叉验证（页面计时与 hilog 时间戳一致）；P95 需多次采样
  正式发布前补采，本报告如实标注为单样本点。

## M6-03 隐私与安全（SDD 6.3）

- 权限：`entry/src/main/module.json5` 与 `AppScope/app.json5` **无 requestPermissions 声明**（离线应用，无 INTERNET/存储权限）。
- 网络：不做任何 network 请求；Web 资源全部来自 rawfile（editor.html/preview.html 内联 bundle）。
- 日志脱敏：应用 hilog 仅输出业务摘要（`[打开] N 字符`、`[保存] 状态`、命令名），**不输出正文/路径全文/剪贴板内容**；
  异常日志 `JSON.stringify(e)` 为错误对象。正文主副本仅存 CM 内存与 library/drafts 私有目录。
- HTML 安全：markdown-it `html:false` + sanitizeHref + 自研 HtmlSafety 白名单检测（M3-01 真机验证
  `<script>` 转义为 `&lt;script&gt;`，未执行；事件属性/危险 iframe 检出）。
- 依赖：oh-package.json5 无三方依赖；web-tools 仅 codemirror 6.x 与 markdown-it 15（本地打包，不联网）。
- 分享：剪贴板通道（R-18），分享前强制保存最新内容，不触碰源文件。

## M6-04 发布准备

- 仓库不设置 signingConfigs（签名材料在工程外 `../local-sign/`，`docs/spikes/external-uri.md` 记录链路）。
- 构建产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`（unsigned）+ 本地 CA 签名
  `../local-sign/entry-signed-local.hap`（Debug profile，交付说明见下文）。
- Release：`-p buildMode=release` 构建验证见 M6-04 执行记录；正式上架需 release profile（R-11 已闭环本地安装链路）。

## 结论

M6-01 布局、M6-02 S1–S4、M6-03 隐私扫描完成并记录；S2 逐键输入响应与多形态响应式复测为
明确的后续人工/工具补测项（已在验收文档标注）。