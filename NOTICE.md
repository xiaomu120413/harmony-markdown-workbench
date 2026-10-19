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
| CodeMirror 6 / markdown-it | 已使用的本地 Web 编辑与 Markdown 解析依赖，实际版本见 web-tools/package-lock.json；未引入 DOMPurify |

## HTML 内容块（ST-HTML-002）

HTML/CSS 解析在本地 Web 运行时完成，不执行被解析文档中的脚本。直接依赖固定版本，传递依赖由 lockfile 固定。许可证原文随 HAP 的 rawfile/licenses 分发：

| 组件 | 版本 | 许可证原文 | 来源 |
|---|---|---|---|
| htmlparser2 | 12.0.0 | [MIT](entry/src/main/resources/rawfile/licenses/htmlparser2.txt) | https://github.com/fb55/htmlparser2 |
| css-tree | 3.2.1 | [MIT](entry/src/main/resources/rawfile/licenses/css-tree.txt) | https://github.com/csstree/csstree |
| domelementtype | 3.0.0 | [BSD-2-Clause](entry/src/main/resources/rawfile/licenses/domelementtype.txt) | https://github.com/fb55/domelementtype |
| domhandler | 6.0.1 | [BSD-2-Clause](entry/src/main/resources/rawfile/licenses/domhandler.txt) | https://github.com/fb55/domhandler |
| domutils | 4.0.2 | [BSD-2-Clause](entry/src/main/resources/rawfile/licenses/domutils.txt) | https://github.com/fb55/domutils |
| dom-serializer | 3.1.1 | [MIT](entry/src/main/resources/rawfile/licenses/dom-serializer.txt) | https://github.com/cheeriojs/dom-serializer |
| entities | 8.0.0 | [BSD-2-Clause](entry/src/main/resources/rawfile/licenses/entities.txt) | https://github.com/fb55/entities |
| mdn-data | 2.27.1 | [CC0-1.0](entry/src/main/resources/rawfile/licenses/mdn-data.txt) | https://github.com/mdn/data |
| source-map-js | 1.2.2 | [BSD-3-Clause](entry/src/main/resources/rawfile/licenses/source-map-js.txt) | https://github.com/7rulnik/source-map-js |

参考项目（仅作调研，未复制代码）：Markor、MarkText、Harmony-Markdown-Editor、SiYuan-HarmonyOS（SDD 22 章）。引用任何开源代码前重新核对许可证。
