# M0-03 尖峰：ArkWeb 编辑运行时

> 状态：**进行中**（代码与构建完成；真机 UI 必测项受 R-13 锁屏阻塞，待解锁后执行）。
> 执行日期：2026-08-29。分支：feature/m0-editor-runtime-spike。

## 1. 已完成验证（真机 OpenHarmony 7.0.0.28）

| 项 | 结果 | 证据 |
|---|---|---|
| ArkWeb 加载本地 rawfile 页面 | ✅ | Web 组件 `resource:/RAWFILE/web/editor.html` + `onPageEnd` 触发（"页面加载完成"日志） |
| CodeMirror 6 本地打包 | ✅ | esbuild 打包 `editor.bundle.js`（2.2MB，含全部依赖）入 rawfile，离线可用 |
| 原生→Web 命令（loadDocument） | ✅ | 点"示例"后日志"已加载示例 Markdown"+`__editorApi` 正常调用 |
| Web→原生事件（jsProxy） | ✅ | `__nativeBridge.postMessage` 通道建立（ready/dirtyChanged 事件到达） |
| runJavaScript 直接返回值 | ⚠️ 不可靠 | `getSnapshot()` 返回 null（ArkWeb 26 Beta 返回值传递问题）→ **已改为事件推送**（requestSnapshot/requestDiagnostics，SDD 8.4 请求式快照协议方向） |
| 主题切换（setTheme） | ⏳ 待解锁复测 | 代码就绪 |

## 2. 待验证矩阵（R-13 锁屏阻塞，设备解锁后执行）

| 必测项（SDD M0-03） | 验证方式 | 状态 |
|---|---|---|
| 中文拼音连续输入 5 分钟 | 编辑器点击→输入法→快照验证 | 待解锁 |
| 组合输入期间不触发脏标记误报 | dirtyChanged 事件计数 | 待解锁 |
| 剪切/复制/粘贴/选择/撤销重做 | 快捷键/工具栏 + 快照对比 | 待解锁 |
| 1MB / 5MB 文档打开与输入 | loadDocument 大文本 + 输入响应 | 待解锁 |
| 前后台切换/窗口变化不丢内容 | 切后台→回前台快照对比 | 待解锁 |
| ArkWeb 进程异常恢复路径 | kill web 进程→重建 | 待解锁（M2 深入） |
| 内存与滚动性能（长文） | 诊断事件返回 len + 帧率观察 | 待解锁 |

**解锁后操作步骤**（已安装 build m03c）：
1. 解锁设备 → `aa start -b com.markdownworkbench.app -a EntryAbility`
2. 首页 → "M0-03 尖峰：编辑器" → 点"示例" → 点"诊断"（验证 CM 状态与文档长度）
3. 点"快照"（验证事件推送链路）
4. 中文输入：点击编辑器区域 → 系统输入法拼音输入 → "快照"验证
5. 长文：通过"示例"加载扩展（或由诊断验证）

## 3. 架构确认（对 M2 的影响）

- **ArkWeb + CodeMirror 6 方案可行性初步成立**（加载/运行/双向桥均通）。
- **快照与内容传输采用"事件推送"而非 runJavaScript 返回值**——协议设计（M2-02）需以本尖峰实测为准：原生→Web 命令用 runJavaScript，Web→原生数据一律走 jsProxy 事件（payload 为 JSON 字符串）。
- Web 资源构建命令固化：`node web-tools/build-web.js`（esbuild 打包到 rawfile）。
- 依赖（@codemirror/*）版本固定于 `web-tools/package-lock.json`，许可证入 NOTICE（M2-01 补充完整清单）。

## 4. 环境限制

- **R-13**：设备重启后进入锁屏（"未登录用户需要输入密码"），`aa start` 报 10106102（screen locked）；无命令行解锁途径（安全机制，需用户密码）。M0-03 剩余 UI 验证待解锁。