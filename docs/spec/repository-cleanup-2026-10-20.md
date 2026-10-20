# 仓库清理与未使用文件审计（2026-10-20）

本轮目标是删除构建产物、历史临时文件和无引用脚本，同时保留发布、审计和签名所需的材料。

## 删除

| 文件/目录 | 原因 |
|---|---|
| `build-logs/`（约 25 MB） | 历史构建日志、源码备份、临时 Python 脚本、演示帧，均为本地生成物 |
| `entry/build/`（约 12 MB） | Debug/Release 构建输出，可由 `hvigorw assembleHap` 重建 |
| `.hvigor/`（约 13 MB） | hvigor 缓存，可由构建重建 |
| `entry/.test/`（约 14 MB） | 本地单测输出 |
| `design-mockup.html` | V0.4.3 设计稿，全仓库无引用 |
| `docs/ux/controls/` 下 6 张单独 before/after 图 | 已有同视口对照合成图，原图无任何文档引用 |
| `scripts/gen-icons.ps1` | 只是 `gen-icons.py` 的 Windows 包装，文档统一使用 `.py` |
| 旧目录 `harmony-markdown-workbench/` | 项目已更名为 `mumark`，迁移后残留的空壳目录 |

## 保留

| 文件/目录 | 原因 |
|---|---|
| `sign_tools/` | 发布签名证书与私钥材料；已加入 `.gitignore`，不得入库 |
| `docs/store/` | 应用市场截图、文案和尺寸清单，提交审核需要 |
| `docs/ux/`、`docs/spec/` 日期化验收记录 | README/acceptance 引用，属于发布审计证据 |
| `entry/src/main/resources/rawfile/licenses/` | 第三方许可证，分发必须保留 |
| `AppScope/resources/base/media/app_icon.svg` | 图标母版产物，`docs/brand/README.md` 记录生成方式 |
| `web-tools/node_modules/`、`oh_modules/` | 构建与测试依赖，可由 lockfile 重建，但不是无用文件 |

## 脚本清单

| 脚本 | 用途 | 入口 |
|---|---|---|
| `scripts/test-*.cjs`（9 个） | 宿主机测试 | `.github/workflows/ci.yml` |
| `scripts/check-docs.mjs` | Markdown 编码与本地链接检查 | CI |
| `scripts/check-source-encoding.mjs` | 源码严格 UTF-8 检查 | CI |
| `scripts/check-source-size.mjs` | 500 行单文件门禁 | CI |
| `scripts/clean-build.sh` / `.bat` | 无缓存构建 + 测试 | README |
| `scripts/sign-local.sh` | 本地签名 HAP | README |
| `scripts/gen-icons.py` | 图标母版重建 | `docs/brand/README.md` |
| `scripts/generate-store-assets.py` | 应用市场素材生成 | `docs/spec/store-materials-2026-10-20.md` |
| `scripts/lib/ets-loader.cjs` | ArkTS 源码加载器 | 宿主机测试 |
| `scripts/lib/editor-write-cases.cjs` | 编辑器/文档/重命名用例 | `test-host.cjs` |

## 扫描结果

- `entry/src/main/ets` 无未被任何文件 import 的 `.ets` 源文件。
- 21 个 `*.test.ets` 全部在 `entry/src/test/List.test.ets` 注册。
- 所有脚本均被 CI、README 或规格文档引用；无其它无引用脚本。
- 图标、Web bundle、许可证和验收截图均有引用或法务用途。
- web-tools 依赖已按实际 import 清理，第三方许可证汇总见 `NOTICE.md` 与 `rawfile/licenses/web-runtime.txt`。

## 验证

- `node scripts/test-host.cjs`：255/255
- `node scripts/test-editor-actions.cjs`：24/24
- 其余脚本测试、`hvigorw test`、Debug/Release `assembleHap`：通过
- `git diff --check`、文档链接检查：通过

## 维护约定

- 构建日志、HAP、缓存和临时截图不提交；`build-logs/`、`entry/build/`、`.hvigor/` 已在 `.gitignore`。
- 签名材料只保留在本地 `sign_tools/`，不进入 Git。
- 日期化验收记录如需精简，应先更新 README/acceptance 的引用，再删除对应证据文件。
