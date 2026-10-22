# 脚本索引

脚本按用途分为三个目录，避免测试、检查和构建相互混杂。

## build/ — 构建、签名与素材

| 脚本 | 用途 |
|---|---|
| `clean-build.sh` / `clean-build.bat` | 清缓存、安装依赖、构建和 SDK 测试，核对本次逐例断言与覆盖率，拒绝旧结果 |
| `sign-local.sh` | 用本地 CA 材料签名 Debug HAP |
| `gen-icons.py` | 从 `docs/brand` 母版重建应用图标 |
| `generate-store-assets.py` | 生成应用市场截图、文案与尺寸清单 |

## check/ — 静态门禁

| 脚本 | 用途 |
|---|---|
| `check-docs.mjs` | Markdown UTF-8 与本地链接检查 |
| `check-sdk-results.mjs` | SDK 编译成功、结果新鲜度、逐例断言和覆盖率检查；保留 Previewer 原始诊断 |
| `check-source-encoding.mjs` | 源码/配置/文档严格 UTF-8 检查 |
| `check-source-size.mjs` | 手写文件 500 行上限 |

## test/ — 宿主机测试

| 脚本 | 用途 |
|---|---|
| `test-host.cjs` | 领域/服务/基础设施与编辑器写回、预览缓存 |
| `test-editor-actions.cjs` | 编辑器/首页控制器场景 |
| `test-file-transactions.cjs` | 另存、导出、交付与文件事务 |
| `test-clipboard-image.cjs` | 系统图片粘贴事件、图片校验与失败附件清理 |
| `test-external-access.cjs` | 外部 URI 授权与访问 |
| `test-page-viewmodels.cjs` | 设置/恢复 ViewModel |
| `test-system-theme.cjs` | 系统主题、手动偏好与原生模式同步 |
| `test-window-viewport.cjs` | 窗口与安全区域 |
| `test-html-preview.cjs` | HTML 只读预览 |
| `test-html-resources.cjs` | HTML 资源解析 |
| `test-html-embed.cjs` | HTML 内容块、预览 iframe/图片复用与资源解析 |
| `lib/ets-loader.cjs` | ArkTS 源码加载器 |
| `lib/editor-write-cases.cjs` | 编辑器写回、文档载入、重命名用例 |

常用命令：

```bash
node scripts/check/check-docs.mjs
node scripts/test/test-host.cjs
bash scripts/build/clean-build.sh
```

CI 清单见 `.github/workflows/ci.yml`。
