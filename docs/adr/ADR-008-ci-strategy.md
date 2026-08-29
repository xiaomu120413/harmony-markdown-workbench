# ADR-008：CI 与无缓存验证策略

- 状态：接受。
- 背景：GitHub-hosted runner 不提供 HarmonyOS SDK（需要 DevEco Studio 授权组件），无法直接运行 CI；SDD 12/13 要求"CI 在无缓存环境成功"可复现执行。
- 决策：
  1. 本地等价验证：`scripts/clean-build.sh`（及 `.bat`）删除项目内缓存（oh_modules/.hvigor/build/entry/.test）后依次执行 ohpm install → assembleHap → test，并在测试日志中检查 hypium 断言 ERROR（门禁，见 R-07）。M0-01 已用该脚本完整通过。
  2. `.github/workflows/ci.yml` 预留，使用 `self-hosted` runner 标签；在自托管 runner 实跑通过前，**不将 workflow 视为已生效门禁**，避免"声称未实际运行的测试通过"。
  3. 测试依赖（hypium/hamock）通过 ohpm 固定版本并纳入 oh-package-lock.json5。
- 后果：无云 CI 自动拦截；合并前由 clean-build 脚本负同等责任。计划在 M0 期间配置自托管 runner（或确认 HarmonyOS 官方 CI 方案）。
- 关联：A-05、R-06；TASK-M0-01 验收点"CI 在无缓存环境成功"（以 clean-build 等价执行）。