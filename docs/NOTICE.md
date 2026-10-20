# NOTICE

第三方组件与许可证清单。引入新依赖前必须核对许可证、版本、维护状态与分发义务（SDD 阶段 0 第 8 条）。

## 测试依赖

| 组件 | 版本 | 用途 | 许可证 | 来源 |
|---|---|---|---|---|
| @ohos/hypium | 1.0.21 | 单元测试框架 | Apache-2.0 | ohpm.openharmony.cn |
| @ohos/hamock | 1.0.0 | 测试 mock 库 | Apache-2.0 | ohpm.openharmony.cn |

## Web 运行时依赖（随 HAP 打包）

版本以 `web-tools/package-lock.json` 为准。所有直接依赖与传递依赖的完整许可证原文见
[`entry/src/main/resources/rawfile/licenses/web-runtime.txt`](../entry/src/main/resources/rawfile/licenses/web-runtime.txt)
（39 个包，构建时从 `web-tools/node_modules` 汇总）。

| 组件 | 版本 | 用途 | 许可证 |
|---|---|---|---|
| codemirror | 6.0.2 | CodeMirror 6 元包（含 autocomplete/search/lint/language） | MIT |
| @codemirror/commands | 6.11.0 | 撤销重做、快捷键命令 | MIT |
| @codemirror/lang-markdown | 6.5.2 | Markdown 语法支持 | MIT |
| @codemirror/state | 6.7.1 | 编辑器状态与变更 | MIT |
| @codemirror/view | 6.43.9 | 编辑器视图与选区 | MIT |
| markdown-it | 15.0.1 | Markdown 解析 | MIT |
| markdown-it-task-lists | 2.1.1 | 任务列表 | ISC |
| markdown-it-footnote | 4.0.0 | 脚注 | MIT |
| markdown-it-mark | 4.0.0 | `==高亮==` | MIT |
| highlight.js | 11.12.0 | 代码块高亮 | BSD-3-Clause |
| htmlparser2 | 12.0.0 | HTML 内容块解析 | MIT |
| css-tree | 3.2.1 | HTML 内容块 CSS 处理 | MIT |

CodeMirror/Lezer、linkify-it、entities 等传递依赖同样随 bundle 分发，名称、版本与许可证原文均在上面的 `web-runtime.txt` 中。
当前未引入 DOMPurify。

## 构建工具链（不随 HAP 分发）

| 组件 | 说明 |
|---|---|
| @ohos/hvigor / hvigor-ohos-plugin | hvigor 6.26.1，位于 `{DEVECO_STUDIO_PATH}/tools/hvigor`，工程 wrapper 转发调用 |
| esbuild | 0.28.2（MIT），仅用于本地打包 Web bundle，不进入 HAP |
| @ohos/hypium / @ohos/hamock | 仅测试构建使用 |

## HTML 内容块（ST-HTML-002）

HTML/CSS 解析在本地 Web 运行时完成，不执行被解析文档中的脚本。直接依赖固定版本，传递依赖由 lockfile 固定。许可证原文随 HAP 的 rawfile/licenses 分发：

| 组件 | 版本 | 许可证原文 | 来源 |
|---|---|---|---|
| htmlparser2 | 12.0.0 | [MIT](../entry/src/main/resources/rawfile/licenses/htmlparser2.txt) | https://github.com/fb55/htmlparser2 |
| css-tree | 3.2.1 | [MIT](../entry/src/main/resources/rawfile/licenses/css-tree.txt) | https://github.com/csstree/csstree |
| domelementtype | 3.0.0 | [BSD-2-Clause](../entry/src/main/resources/rawfile/licenses/domelementtype.txt) | https://github.com/fb55/domelementtype |
| domhandler | 6.0.1 | [BSD-2-Clause](../entry/src/main/resources/rawfile/licenses/domhandler.txt) | https://github.com/fb55/domhandler |
| domutils | 4.0.2 | [BSD-2-Clause](../entry/src/main/resources/rawfile/licenses/domutils.txt) | https://github.com/fb55/domutils |
| dom-serializer | 3.1.1 | [MIT](../entry/src/main/resources/rawfile/licenses/dom-serializer.txt) | https://github.com/cheeriojs/dom-serializer |
| entities | 8.0.0 | [BSD-2-Clause](../entry/src/main/resources/rawfile/licenses/entities.txt) | https://github.com/fb55/entities |
| mdn-data | 2.27.1 | [CC0-1.0](../entry/src/main/resources/rawfile/licenses/mdn-data.txt) | https://github.com/mdn/data |
| source-map-js | 1.2.2 | [BSD-3-Clause](../entry/src/main/resources/rawfile/licenses/source-map-js.txt) | https://github.com/7rulnik/source-map-js |

参考项目（仅作调研，未复制代码）：Markor、MarkText、Harmony-Markdown-Editor、SiYuan-HarmonyOS（SDD 22 章）。引用任何开源代码前重新核对许可证。
