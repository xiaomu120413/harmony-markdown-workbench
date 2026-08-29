# ADR-006：工具链与 SDK 版本基线

- 状态：接受（M0-01 实测确认）。
- 背景：本机唯一 SDK 为 HarmonyOS 6.6.0 Beta1（API 26，`oh-uni-package.json` 26.0.0.23，releaseType Beta1），hvigor 6.26.1、ohpm 26.0.0.410。SDD 要求 M0-01 确定 target/minimum SDK；同目录已验证工程 `PythonExecDemo` 使用 `6.0.2(22)` 组合构建成功。
- 决策：
  1. targetSdkVersion = compatibleSdkVersion = `6.0.2(22)`（HarmonyOS 6.0.2 / API 22），runtimeOS = HarmonyOS；M0-01 构建已验证通过（HAP 产出）。
  2. 工程 wrapper 采用**转发模式**：不复制 DevEco 官方 `hvigorw.js` 到工程内（该脚本以自身位置推导 hvigor 主包路径，`resolve(__dirname, "..")`，复制后链接会指向错误位置——实测故障），而是由 `hvigorw`/`hvigorw.bat` 定位 `DEVECO_STUDIO_PATH` 并转发到官方 `tools/hvigor/bin/hvigorw.js`。
  3. 根 `build/` 目录由 hvigor 作为项目输出目录管理（启动时可能清理）；自定义日志放 `build-logs/`。
- 后果：换机/换环境要求安装 DevEco Studio 并设置 `DEVECO_STUDIO_PATH`；API 26 SDK 为 Beta 版本，正式发布前需按发布工具链复核（R-08）。
- 关联：A-01、A-07；TASK-M0-01。