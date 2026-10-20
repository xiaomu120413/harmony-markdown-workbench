# 手机、平板回归 ST-MOBILE-REGRESSION-001

## 范围与验收

基线 34ad2bf，用户要求回归菜单闪烁、最近列表和直接删除；文件不超过 500 行，发现问题即修复并提交推送。

- 手机 Pura 90 模拟器 API 24，以及 MatePad Pro API 22 真机。
- 标题、格式、段落、插入：选择项目与点击外部关闭，检查关闭后是否重新弹出；保留关闭截图采样及 UI 状态证据。
- 新文档保存后最近记录及时刷新，置顶及列表打开正常；平板同时检查编辑器侧栏筛选和当前文档删除保护。
- 直接删除确认说明不可恢复；取消保留文件，确认移除源文件、对应草稿及最近记录；重启不重新出现，不新增回收副本。
- 仅操作自建验收文档，保留设备已有文档；不增加权限、运行态抽象或无关功能。

## 验证记录

2026-10-20，Windows / DevEco Studio 当前 SDK。未发现新的产品缺陷，本次仅补充回归记录及截图，不修改运行时代码、权限或包名。

| 环境 | 结果 |
|---|---|
| Pura 90 手机模拟器，OpenHarmony 6.1.1.125 / API 24，1320×2856 | 四组菜单选择及外点关闭、最近列表置顶、取消/确认直接删除、重启通过 |
| MatePad Pro PCE-W30 真机，OpenHarmony 6.0.2.130 / API 22 | 1920×2880 竖屏四组菜单选择与软键盘通过；2880×1920 横屏外点关闭、左侧列表筛选及直接删除通过 |

两端均从 34ad2bf 构建同一份 Release 代码，以独立验证包 com.mumark.menutest 签名安装。
正式 com.mumark.app 未覆盖或卸载；AppScope/app.json5 已恢复正式包名和 1.0.0，最终重新构建正式 Release。

### 菜单与最近列表

1. 手机和平板竖屏均实际执行标题 H2、格式加粗、段落任务列表、插入分隔线。正文变化正常；每组选择前截图，选择后连续 6 次 snapshot_display 采样，后续 UI 树无残留 MenuItem，未复现关闭后重弹或切换成其他菜单内容。
2. 手机和平板横屏逐组点击菜单外部关闭，UI 树均从对应菜单项变为零项。平板横屏标题菜单另保留 6 次关闭采样。软键盘弹出、收起及实体旋转后工具栏仍可用，平板编辑器左侧列表保留。
3. 新建保存后最近记录及时刷新；手机置顶后该条移至首位，点击图钉没有误打开文档。平板编辑器置顶筛选能找到该文档；搜索不存在的名称显示“没有匹配的文档”，清空后恢复列表。
4. 平板编辑器点击当前文档删除，未弹出删除确认，文件仍在；切回首页才可删除。手机重启后从列表打开原有文档正常，四组菜单外点关闭不修改正文，文件校验值保持不变。

### 直接删除与数据保留

仅删除本轮自建 MuMark-Mobile-1922中.md 和 MuMark-Tablet-1923中.md；自动化输入使用临时哨兵，故文件名带“中”，正文校验已确认哨兵清除，按实际文件名验收。

- 两端删除弹窗均明确“文件将直接删除，无法恢复”；取消后原文件仍为 33 字节，记录保留。
- 确认后，hdc shell ls 检查对应 library 源文件不存在；最近记录同步移除。aa force-stop 后重新启动，删除项没有重新出现，“我的文档”也无该文件、回收站或恢复入口。
- 手机旧 library/.trash 删除前后均为空，平板未建立回收目录。两端 drafts 最终为空；没有新增回收副本。
- 手机原有加粗文本.md 全程保留，验收前后 SHA-256 均为 761a0a90e15b80dd9cd69cf4d100f95ae0dc90121210b23514cb7c48d00eb232。
- 本轮设备沙箱拒绝写入人工草稿（普通 file send、shell cp 返回 Permission denied），因此未在手机/平板注入残留草稿验证清理，不提升权限。对应草稿清理、删除失败保留草稿及当前文档保护已由下述控制器测试覆盖；此前 2in1 实机的残留草稿删除证据见既有记录。

### 命令与结果

| 命令 | 结果 |
|---|---|
| node scripts/test/test-host.cjs | 258/258 通过，平台 IO 为 mock；包含临时文件删除及不建立回收副本 |
| node scripts/test/test-editor-actions.cjs | 40 场景通过，真实控制器、平台边界 mock |
| node scripts/test/test-file-transactions.cjs | 24 场景通过 |
| hvigorw.bat test --mode module -p product=default | BUILD SUCCESSFUL；test_result.txt：205 通过，Failure 0、Error 0 |
| hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release | 正式包 BUILD SUCCESSFUL；仓库未配置正式签名，正式产物为 unsigned HAP |
| node scripts/check/check-source-size.mjs | 128 个手写源码/测试/脚本均不超过 500 行 |
| node scripts/check/check-source-encoding.mjs、node scripts/check/check-docs.mjs、git diff --check | UTF-8、文档链接及差异检查通过 |

代表截图：[手机格式菜单](../ux/mobile-menu-close-2026-10-20.jpg)、[平板竖屏段落菜单](../ux/tablet-menu-close-2026-10-20.jpg)、[平板横屏外点关闭](../ux/tablet-landscape-menu-2026-10-20.jpg)、[不可恢复删除确认](../ux/tablet-direct-delete-2026-10-20.jpeg)。
完整原始采样保留在忽略目录 build-logs/mobile-{heading,format,paragraph,insert}-*.jpeg、tablet-{heading,format,paragraph,insert}-*.jpeg；构建和测试日志为 mobile-*.log，不提交构建产物或签名材料。

边界：截图连续采样不是高帧率录屏，不能量化瞬时每帧闪烁；手机本轮使用模拟器，未覆盖实体手机厂商键盘差异。残留草稿设备注入受限如上。外部原文件仍需文件管理器删除，不新增目录或其他敏感权限。
