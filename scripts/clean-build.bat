@echo off
rem TASK-M0-01 clean-build：模拟无缓存环境从零构建并执行测试门禁。
rem 删除项目内缓存（oh_modules/.hvigor/build/.test）后：ohpm install → assembleHap → test。
rem 门禁：测试日志中出现 hypium 断言错误（hvigor 对用例失败仍返回成功）即判定失败。
setlocal enabledelayedexpansion
cd /d %~dp0..

set "OHPM="
if defined DEVECO_STUDIO_PATH (
  if exist "%DEVECO_STUDIO_PATH%\tools\ohpm\bin\ohpm.bat" set "OHPM=%DEVECO_STUDIO_PATH%\tools\ohpm\bin\ohpm.bat"
)
if not defined OHPM (
  if exist "C:\Program Files\Huawei\DevEco Studio\tools\ohpm\bin\ohpm.bat" set "OHPM=C:\Program Files\Huawei\DevEco Studio\tools\ohpm\bin\ohpm.bat"
)
if not defined OHPM (
  echo ERROR: DevEco Studio ohpm not found. Set DEVECO_STUDIO_PATH. 1>&2
  exit /b 1
)

rem 根 build/ 目录由 hvigor 作为项目输出目录管理（启动时可能清理），日志放在 build-logs/。
set "LOG=%CD%\build-logs\clean-build.log"

echo [clean-build] cleaning caches: oh_modules, .hvigor, build, entry/build, entry/.test
if exist oh_modules rmdir /s /q oh_modules
if exist entry\oh_modules rmdir /s /q entry\oh_modules
if exist .hvigor rmdir /s /q .hvigor
if exist build rmdir /s /q build
if exist entry\build rmdir /s /q entry\build
if exist entry\.test rmdir /s /q entry\.test
if not exist build-logs mkdir build-logs

echo [clean-build] ohpm install
call "%OHPM%" install > "%LOG%" 2>&1
if errorlevel 1 ( echo ohpm install failed, see %LOG% & exit /b 1 )

echo [clean-build] assembleHap ^(debug^)
call hvigorw.bat assembleHap --mode module -p product=default >> "%LOG%" 2>&1
if errorlevel 1 ( echo assembleHap failed, see %LOG% & exit /b 1 )

echo [clean-build] test
call hvigorw.bat test --mode module -p product=default >> "%LOG%" 2>&1
if errorlevel 1 ( echo test failed, see %LOG% & exit /b 1 )

rem Gate: hypium assertion failures appear as ERROR lines while hvigor still returns success.
findstr /C:"ERROR" "%LOG%" > NUL
if not errorlevel 1 (
  echo TEST GATE: test log contains ERROR lines ^(possible assertion failure^), treat as failed. see %LOG%
  findstr /C:"ERROR" "%LOG%" | findstr /n "." | findstr /b "[1-9]" | head -10 2> NUL
  exit /b 1
)

echo [clean-build] BUILD OK. log: %LOG%
dir /b entry\build\default\outputs\default\*.hap 2>NUL