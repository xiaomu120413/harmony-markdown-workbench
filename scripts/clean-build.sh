#!/usr/bin/env bash
# TASK-M0-01 clean-build：模拟无缓存环境从零构建并执行测试门禁。
# 删除项目内缓存（oh_modules/.hvigor/build/.test）后：ohpm install → assembleHap → test。
# 门禁：测试日志中出现 hypium 断言错误（hvigor 对用例失败仍返回成功）即判定失败。
set -u

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# ---- 定位 DevEco 工具（ohpm）----
DEVECO_TOOLS=""
if [ -n "${DEVECO_STUDIO_PATH:-}" ] && [ -d "${DEVECO_STUDIO_PATH}/tools" ]; then
  DEVECO_TOOLS="${DEVECO_STUDIO_PATH}/tools"
elif [ -d "C:/Program Files/Huawei/DevEco Studio/tools" ]; then
  DEVECO_TOOLS="C:/Program Files/Huawei/DevEco Studio/tools"
else
  echo "ERROR: DevEco Studio not found. Set DEVECO_STUDIO_PATH." >&2
  exit 1
fi
OHPM="${DEVECO_TOOLS}/ohpm/bin/ohpm"

# 根 build/ 目录由 hvigor 作为项目输出目录管理（启动时可能清理），日志放在 build-logs/。
LOG="${ROOT}/build-logs/clean-build.log"

echo "[clean-build] 清理项目内缓存：oh_modules, .hvigor, build, entry/build, entry/.test"
rm -rf oh_modules entry/oh_modules .hvigor build entry/build entry/.test
mkdir -p "${ROOT}/build-logs"

echo "[clean-build] ohpm install"
"${OHPM}" install > "${LOG}" 2>&1 || { echo "ohpm install 失败，见 ${LOG}"; exit 1; }

echo "[clean-build] assembleHap (debug)"
./hvigorw assembleHap --mode module -p product=default >> "${LOG}" 2>&1 \
  || { echo "assembleHap 失败，见 ${LOG}"; exit 1; }

echo "[clean-build] test"
./hvigorw test --mode module -p product=default >> "${LOG}" 2>&1 \
  || { echo "test 失败，见 ${LOG}"; exit 1; }

# 门禁：hypium 用例失败表现为日志中的断言 ERROR（hvigor 任务仍可能返回成功）。
if grep -qE "ERROR( |:)" "${LOG}"; then
  echo "TEST GATE: 测试日志包含 ERROR（可能为断言失败），视为未通过。见 ${LOG}"
  grep -E "ERROR( |:)" "${LOG}" | head -10
  exit 1
fi

echo "[clean-build] BUILD OK. 日志：${LOG}"
echo "[clean-build] 关键产物："
ls -la entry/build/default/outputs/default/*.hap 2>/dev/null