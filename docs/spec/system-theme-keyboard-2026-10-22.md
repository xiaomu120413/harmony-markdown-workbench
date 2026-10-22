# 系统主题与键盘补验 ST-QUALITY-002

REQ-QUALITY-002：增加跟随系统主题，保留用户明确选择的浅色/深色；实时更新原生界面、编辑器与预览。补验 PC 主要任务流的键盘导航、系统分屏比例及 API 24 手机模拟器，并更新自测报告。

设计：沿用 ThemeMode、SettingsStore、AppTheme 和页面既有 ViewModel；新增 system 选项，新配置默认 system，旧 light/dark 配置保持原值。系统原生主题使用 COLOR_MODE_NOT_SET，UIAbility 初始化并发布实际 colorMode 配置，页面响应变化，禁止通过计数器重建 Web。模式解析在既有 AppTheme 内完成，正文、选择区与保存状态不因切换主题重新载入。

键盘验收从现有原生按钮与 Web 焦点路径开始，先复现实际缺口再修改；需要可聚焦的文档行优先使用原生按钮语义，不建通用焦点管理框架。分屏通过系统窗口操作完成，不将应用内编辑/预览分栏当作系统分屏。

边界：仅操作本任务测试文档，保留用户文件。复用现有调试签名覆盖安装，正式签名材料不变。手写文件不超过 500 行；验证记录区分平台实测、宿主 mock 和未覆盖项。回退可恢复主题枚举、设置与页面配置监听；不改变文档存储格式。

验证计划：主题缺省/旧配置/系统与手动优先级单测、设置存储三种原生模式、动态模式变化不改正文；PC Tab/Shift+Tab、Enter/Space、编辑快捷键和上下文菜单，系统分屏配对后调整比例；手机主题/输入/保存/预览/菜单/安全区回归，编译与静态门禁，DOCX 渲染检查后提交推送。

## 验证结果

2026-10-22：PC HAD-W32 真机 API 26、手机模拟器 API 24；设备与场景细节见 [自测报告](experience-selftest-2026-10-21.md)。仅注入键盘/鼠标事件，不等同于实体外设认证。

- 主题：PC 从系统设置打开深色，再关闭，设置/编辑页实时更新；92 字节正文前后 SHA-256 一致。手机系统深色联动、手动浅色覆盖、跟随系统下深色预览通过；系统开关已恢复关闭。主题刷新宿主用例确认会话、保存编排器、脏状态、正文长度、光标与分屏视图保持，只有样式命令下发，不调用载入文档。
- 键盘：Tab/Shift+Tab 到达设置、最近文档、编辑及预览；Enter 打开最近文档及大纲条目，Space 激活预览和大纲。Ctrl+F 原先只显示面板而未聚焦，修正为原生输入框出现时请求焦点；输入框 Escape 在 IME 前处理并返回编辑区。Ctrl+B/I/Z/Y/S、Ctrl+Home、Shift+End 与 Shift+F10 系统菜单通过，撤销还原后正文哈希不变。删除确认仅取消，不删除任何用户文件。
- 系统分屏：完成窗口配对后，uinput 鼠标拖动比例条，list_windows 记录宽度 1549 → 1031 → 1549、高度 1955；最初向扩大方向拖动被配对应用最小宽度约束，改为缩小后成功。并非应用内分栏比例测试。
- 手机：中文文档保存/重开、查找 1/2 命中、软键盘缩高、Escape 关闭查找、四组菜单打开/退出、深浅色原生界面与预览通过；89 字节落盘正文/空行完整。旋转调试未生效，横屏未完成；没有以静态截图认证闪烁或动画时长。

命令与结果：

- `node scripts/test/test-*.cjs` 中 11 个脚本逐一执行均 exit 0；计数依次见报告。新增 `test-system-theme.cjs` 使用真实 AppTheme、SettingsStore、SettingsViewModel、EditorLifecycle，平台配置/偏好 IO mocked，不能替代设备验证。
- `node scripts/check/check-source-size.mjs`：131 个手写源码/测试/脚本均 ≤500 行；`check-source-encoding.mjs`、`check-docs.mjs` 与 `git diff --check` 通过。
- `web-tools` 中 `node build-web.js` 后，`git diff --exit-code -- entry/src/main/resources/rawfile/web/` 无差异。
- 既有调试签名私有构建目录中运行 `hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release --no-daemon`：33 tasks 成功，两设备 `hdc install -r` 成功，未卸载或清数据。
- 同一源码仅替换为既有正式签名配置后，`hvigorw.bat assembleApp --mode project -p product=default -p buildMode=release --no-daemon`：42 tasks 成功。APP 与 HAP 均 `hap-sign-tool.jar verify-app` 成功、Digest verify true；HAP Profile 哈希与 `sign_tools/MumarkRelease.p7b` 一致。内嵌包名、1.0.0、1000000、API 24 及唯一 FILE_ACCESS_PERSIST 权限核对无误；正式 APP/HAP 哈希见报告，产物仅保留本地 dist，不提交签名材料或包。

构建输出保留已有的 router/getContext 弃用等警告，未新增编译错误。Windows SDK UT 运行器此前报 LocalSocket 写入失败，未取得 SDK UT 通过结论；本次不将宿主测试描述为 SDK UT。未覆盖官方 L1/L2 检测等级对照、云测、功耗/长稳、真实外设插拔、全部授权/异常弹层和手机横屏。DOCX 在交付前渲染并逐页检查，签名及设备回归日志位于本地 build-logs/quality22-*。
