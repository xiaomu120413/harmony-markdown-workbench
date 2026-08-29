# M0-02 尖峰：外部文件 URI 访问

> 状态：**部分完成 + 2 项阻塞**（见结论与风险）。执行日期：2026-08-29。
> 工程：HarmonyMarkdownWorkbench；分支：feature/m0-external-uri-spike。

## 1. 结论摘要

| 主题 | 结论 |
|---|---|
| 签名链路（HAP + profile） | ✅ 完整打通，已固化为 `scripts/sign-local.sh`（官方 OpenHarmony CA 一键签名） |
| 真机安装 | ❌ **本机设备（HUAWEI MateBook Pro / OpenHarmony 7.0.0.28 定制镜像）拒绝调试签名安装**（R-11） |
| persistPermission 持久授权 | ⚠️ **API 26 Beta SDK 类型缺失**，编译期不可调用（R-10）；运行时行为待可调试设备验证 |
| 功能链路（选择/读取/保存/重启） | ⏳ 代码完成、编译通过；真机矩阵待可调试设备执行 |

门禁对照（SDD M0-02）：若无法可靠持久访问，产品必须显示"临时访问"、最近文件改"重新定位"流程 —— **该降级预案由本尖峰证实为 V0.1 必选路径**（在本机设备与当前 SDK 下）。

## 2. 环境

| 项 | 值 |
|---|---|
| 设备 | HUAWEI MateBook Pro（HAD-W32），UDID `C551DB0E3F7562A4FD05763A5B12F54D1C981509FCAF8C885BAE21EFC9B2D311` |
| 系统 | OpenHarmony 7.0.0.28，API 26，3120x2080，root shell 可用 |
| SDK | DevEco Studio 26.0.0.461；ets API 26.0.0.23（Beta1）；hvigor 6.26.1；ohpm 26.0.0.410 |
| 签名工具 | `sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar`；官方材料 `OpenHarmony.p12`（密码 `123456`，RC2 旧式加密，需 `openssl -legacy` 读取） |
| 工程关键参数 | bundleName `com.markdownworkbench.app`；targetSdk `6.0.2(22)` |

## 3. API 层发现（API 26 Beta）

1. **DocumentViewPicker.select() 返回 `Promise<Array<string>>`**（直接是 uri 数组，非对象数组）。`@ohos.file.picker.d.ts:679`。
2. **`@ohos.file.fileuri` 仅提供 `getUriFromPath`**，无 `getName`；文件名需自行从 uri 截取。
3. **`fs.readTextSync(path)` 仅接受路径/URI 字符串**（不接受 fd）；fd 读取需 `readSync(fd, ArrayBuffer)`。
4. **`@ohos.application.uriPermissionManager` 的 namespace 为空**（无 persistPermission/grantUriPermission 声明）——模块增强（declare module）在 ArkTS 编译器下不生效，"Cannot use namespace as a value"。**结论：API 26 Beta 下 persistPermission 编译期不可调用**（R-10）。
5. `DocumentSelectOptions` 有 `authMode`/`multiAuthMode`（批量授权选择模式），无持久化选项。

## 4. 签名链路（已打通，`scripts/sign-local.sh`）

关键参数与坑（全部实测）：

1. **证书**：应用证书由 OpenHarmony 官方 `Application CA` 签发（`generate-app-cert`，issuer keystore = `OpenHarmony.p12`，alias `openharmony application ca`，密码 `123456`）；链 = 叶子 + Application CA + Root CA。
2. **profile**：`debug-info.device-ids` + `device-id-type: udid`（官方 `UnsgnedDebugProfileTemplate.json` 结构）；证书字段必须 **URL-safe base64**（`+`→`-`，`/`→`_`，普通 base64 报 `Illegal base64 character`）。
3. **profile 签名**：`hap-sign-tool sign-profile` 对自签 profile CA 存在"must be a cert chain"行为限制（DevEco 26 工具）；改用 `openssl cms -sign -nodetach`（**必须 `-nodetach` 内嵌 content**，否则设备侧 "no content"），签名者 = `openharmony application profile debug` 私钥（从 p12 以 `-legacy` 导出）。
4. **HAP 签名**：`sign-app -mode localSign`，appCertFile 为证书链文件（扩展名须 `.cer`）。
5. **hvigor signingConfigs 不可脚本化**：密码须 IDE 加密格式（≥32 位 hex 密文 + `material/` 目录），明文被拒 → 工程保持无签名配置，签名全部走脚本（密码不落库，SDD 合规）。

## 5. 设备信任策略（R-11 依据）

- `hap_verify` 实测失败点：`it do not come from trusted root, issuer: CN=OpenHarmony Application Profile Debug`（`hap_cert_verify_openssl_utils.cpp GetCertsChain`）。
- 设备信任配置（`/system/etc/security/`）：
  - `trusted_apps_sources.json`：含 `OpenHarmony apps` 源（app-signing-cert / profile-debug-signing-certificate / root-ca 均为 OpenHarmony 官方 DN）✓
  - `trusted_root_ca.json`：仅 2 个根 —— 华为 CBG Root CA G2 与 **OpenHarmony Application Root CA**；**不含 Profile Debug/Release CA**（profile 签名者须链到 trusted root，而 Profile CA 为自签根 → 必然拒绝）。
- 根文件系统为 **erofs（只读）**，无法向信任库补入 Profile CA；`bm install` 无调试旁路（`-d` 是降级安装）；开发者模式参数已开（`const.debuggable=1`、`developermode.state=true`）仍不可装。
- **结论：本机为华为定制消费级镜像，不开放第三方调试签名安装**（开发板/官方模拟器镜像通常内置 Profile CA 信任）。→ 对 V0.1 的影响：真机调试需更换可调试镜像/设备，或走华为发布签名；如实记录，不假装通过。

## 6. 功能验证矩阵（待执行项）

| 场景 | 状态 | 说明 |
|---|---|---|
| 文件选择（picker） | 待设备验证 | 代码完成（SpikeUriPage ①） |
| URI 读取（openSync/readText） | 待设备验证 | 代码完成 |
| 元数据（stat） | 待设备验证 | 代码完成 |
| 持久化授权（persistPermission） | **编译期不可用** | R-10；SDK 修复前不可调用 |
| 重启后再次访问 | 待设备验证 | 代码完成（preferences 记 URI + 重开按钮 ④） |
| 原位写入 | 待设备验证 | 探针模式（开关控制，⑤） |
| 文件被移动/删除 | 待设备验证 | 代码路径已实现（④ 失败分支） |
| 权限失效（临时访问降级） | **预案确认必选** | SDD M0-02 门禁降级路径 |

## 7. 对架构/规格的影响

1. **FR-FILE-002 验收需修订**：在本机设备与 API 26 Beta 下，持久授权不可实现 → V0.1 默认按"临时访问 + 重新定位"交付，`canPersistAccess()` 返回 false，UI 明示"临时访问"（拟提交 ADR-009 草案）。
2. **签名/安装流程**纳入工程交付物（`scripts/sign-local.sh` + README），M6-04 发布签名仍走 AppGallery。

## 8. 建议下一步

1. 用支持调试安装的镜像（OpenHarmony 官方开发板镜像/模拟器）或 HarmonyOS 设备完成第 6 节矩阵。
2. 正式 SDK 发布后复核 persistPermission 类型与运行时行为（R-10 关闭条件）。
3. 评估华为 AGC 签名/调试通道（A-04）。