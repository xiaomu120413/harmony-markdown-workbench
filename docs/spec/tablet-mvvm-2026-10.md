# 平板验收与 MVVM 边界整理（TASK-TABLET-001）

## 需求与范围

- API 22 实体平板验证横竖屏、安全区、软键盘、编辑 / 查找 / 保存和文件入口。
- 修复正文改变后查找结果不更新的问题；不用刷新计数器驱动视图。
- 检查四个页面的 MVVM 边界，设置及恢复页移出业务与存储编排；保持文件职责单一、手写文件不超过 500 行。
- 不调整文件格式、权限、包划分或 SDK 下限；保留用户数据。

## 设计

EditorState / HomeState 是可观察的展示状态，Controller 与其功能协作者承担 ViewModel 编排；domain 保留纯规则，infrastructure 负责平台 IO。设置与恢复补充 State / ViewModel，页面只连接生命周期、展示和事件。

查找 / 预览读取同一个带 sessionId、version、content 的正文快照，按照当前会话、保存协调器记录的真实正文版本和查找条件接收结果。同内容版本及条件产生相同结果，不增加 requestGeneration / syncGeneration。文档读取以实际 Promise 身份防止旧读操作覆盖新读操作，Promise 属于非观察环境而非 UI 状态。

回滚可撤销本次提交，无数据迁移。

## 验证

环境：2026-10-19，HUAWEI MatePad Pro PCE-W30，HarmonyOS 6.0.2.130 / API 22；横屏 2880×1920、竖屏 1920×2880，密度 2。validation 包覆盖安装保留数据；未覆盖正式包。用户协助实体旋转；调试 `-motion,1` 被系统禁用，未把无效命令算作旋转成功。

### 实体验收

| 场景 | 结果及证据 |
| --- | --- |
| API 22 安装与启动 | 签名 validation HAP 安装成功，首页、编辑器可正常打开；未发现 API 26 Web 属性在 API 22 执行的问题 |
| 横屏软键盘 | 点击正文弹出完整系统键盘，编辑区随 RESIZE 缩短，保存和正文保留；[截图](../ux/tablet/landscape-keyboard.jpg) |
| 非零安全区 | MUMARK-VIEWPORT 日志为 `insets vp={left:0,top:39,right:0,bottom:28}`，键盘可见通知 true；顶部状态栏和底部手势条未遮挡页面 |
| 竖屏及键盘 | 用户实体转为竖屏，查找、正文、分屏预览与键盘同时可见；文档内容保留；[截图](../ux/tablet/portrait-keyboard.jpg)。这属于平板竖屏，不算手机实测 |
| 编辑、保存和重开 | 输入 MatePad 验收文本，点击保存；覆盖安装修复版后最近打开，240 字符测试内容仍存在 |
| 查找实时更新 | 修复前四处 MatePad 仍显示 1/1；修复后查询得到四处，追加一处后无需重开查找即显示 1/5；[截图](../ux/tablet/find-updates.jpg) |
| 设置持久化 | ViewModel 拆分后字号 15→16，返回再进入仍为 16；[截图](../ux/tablet/settings-persisted.jpg)。验收后恢复 15 |
| 恢复页 | 设置中的恢复入口可达，空草稿提示正常；[截图](../ux/tablet/recovery.jpg)。非空恢复写回/失败保护使用现有业务测试和新增 ViewModel 测试，本轮未删除用户草稿制造场景 |

截图仅缩小，来源时间与分辨率见 [captures.json](../ux/tablet/captures.json)。横竖屏基础截图在 MVVM 整理前采集，查找修复、设置持久化、恢复页截图在重构后修复包采集。最终又覆盖安装并做启动检查，最终主机测试和 HAP 构建以命令结果为准。

### 全局检查与修复

1. 设置页、恢复页不再导入或执行 Repository；校验、恢复决策调用和持久化编排进入各自 ViewModel，ArkUI 页面保留展示与事件分发。
2. `requestGeneration`、`syncGeneration` 没有进入最终实现；已有可观察 `loadGeneration` 也移除。异步归属使用文档会话、正文版本、查询条件及读 Promise，不触发强制重绘。
3. 查找和预览共用文档同步防抖快照，纯编辑模式只要查找打开也同步命中，更新命中不抢焦点或修改正文。
4. 设置以串行队列持久化独立快照，失败日志和提示可见，失败不阻断后续保存；离页后的加载结果不再写状态。
5. 首页搜索依据当前查询词接收结果；清空查询立即清除 busy，旧结果不能覆盖；离开首页后的拖入结果不再发起新路由。

### 命令与结果

- `node scripts/test-host.cjs`：234/234。
- `node scripts/test-editor-actions.cjs`：19 组；新增编辑后查找重算、查询变更、销毁后的结果、真实正文版本门控、连续加载相同目标时旧读失效、清空首页搜索。
- `node scripts/test-file-transactions.cjs`：14 组。
- `node scripts/test-page-viewmodels.cjs`：7 组；快速设置串行写入、失败/重试、字号校验、离页加载、恢复冲突和副本失败保留草稿。已加入 CI。
- `node scripts/test-window-viewport.cjs`：8 组。
- `hvigorw.bat test --mode module -p product=default`、`assembleHap --mode module -p product=default -p buildMode=release`：BUILD SUCCESSFUL；日志分别在 `build-logs/tablet-test.log`、`build-logs/tablet-release.log`。保留原有 ESObject / 废弃 API 告警。
- 本地签名验证包构建、覆盖安装成功；生产 bundle 配置恢复后重新构建 Release。
- 源码大小、严格 UTF-8、文档链接、`git diff --check` 通过；手写源码/测试/脚本均不超过 500 行。

未覆盖：实体手机、手机模拟器、中文 IME 拼音组合/候选提交全链路、系统字体放大、分屏窗口间拖放、多文件提供者及平板上的完整导出落盘回归。文本注入和键盘显示不等于中文组合输入验收。本轮未重新声称 API 26 文件交付记录在 API 22 全部复现，相关完整记录仍见 [文件链路回归](file-regression-2026-10.md)。
