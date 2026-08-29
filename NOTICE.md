# NOTICE

第三方组件与许可证清单。引入新依赖前必须核对许可证、版本、维护状态与分发义务（SDD 阶段 0 第 8 条）。

## 当前依赖（M0-01）

| 组件 | 版本 | 用途 | 许可证 | 来源 |
|---|---|---|---|---|
| @ohos/hypium | 1.0.21 | 单元测试框架 | Apache-2.0 | ohpm.openharmony.cn |
| @ohos/hamock | 1.0.0 | 测试 mock 库 | Apache-2.0 | ohpm.openharmony.cn |

## 构建工具链（随 DevEco Studio 分发，非项目依赖）

| 组件 | 说明 |
|---|---|
| @ohos/hvigor / hvigor-ohos-plugin | hvigor 6.26.1，位于 `{DEVECO_STUDIO_PATH}/tools/hvigor`，工程 wrapper 转发调用 |
| CodeMirror 6 / markdown-it / DOMPurify | 规划中的 Web 层依赖（M2-01/M3-01 引入，引入时补录本清单并固定版本） |

参考项目（仅作调研，未复制代码）：Markor、MarkText、Harmony-Markdown-Editor、SiYuan-HarmonyOS（SDD 22 章）。引用任何开源代码前重新核对许可证。