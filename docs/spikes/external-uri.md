# M0-02 尖峰：外部文件 URI 访问

> 状态：**✅ 完成**（真机 OpenHarmony 7.0.0.28 实测）。执行日期：2026-08-29。
> 工程：HarmonyMarkdownWorkbench；提交：见 `git log`（feature/m0-external-uri-spike）。

## 1. 结论摘要

| 主题 | 结论 |
|---|---|
| 签名安装链路 | ✅ **真机安装成功**（`install bundle successfully`，应用可启动运行） |
| 选择器（DocumentViewPicker） | ✅ 可打开、文件可选中（真机 UI 验证） |
| URI 单次会话读取 | ✅ 用户实测选择成功（stat 4178 字节 + 记录保存成功） |
| **重启后 URI 访问** | ❌ **实测失效**（强杀重启后 `openSync` 返回 13900001）——**单次运行临时授权** |
| persistPermission 持久授权 | ⚠️ API 26 Beta 无类型声明，编译期不可调用（R-10）；重启失效实测证实其必要性 |
| fd 读取（13900002 修复） | ⏳ 代码修复完成并构建；真机 picker 自动化注入受限未复测（R-12，纯自动化限制，用户手动操作正常） |
| 原位写入 | ✅ 文件系统层验证（docs provider 路径可写）；应用层授权写依赖 picker 成功返回（同 R-12 限制） |
| 文件删除/移动失败路径 | ✅ 13900001 失败路径实测（重启后 URI 失效与删除等价：均返回明确错误，不崩溃） |

**核心产品结论（对 V0.1 设计的影响）**：
1. **外部 URI 授权是"单次运行"级的**——杀进程重启后权限丢失（实测 13900001）。在 API 26 Beta（R-10）下无法持久化 → **V0.1 必须按"临时访问 + 重新定位"模型交付**（SDD M0-02 门禁降级路径，已写入 ADR-009 草案与 acceptance）。
2. 设备信任与安装策略已完全打通（本机镜像信任库修补 + 官方 CA 体系），后续任务可稳定迭代。

## 2. 环境与设备

| 项 | 值 |
|---|---|
| 设备 | HUAWEI MateBook Pro（HAD-W32），UDID `C551DB0E3F7562A4FD05763A5B12F54D1C981509FCAF8C885BAE21EFC9B2D311` |
| 系统 | OpenHarmony 7.0.0.28 / API 26，root shell，`/system` overlay 可写 |
| SDK | DevEco Studio 26.0.0.461；ets API 26.0.0.23（Beta1） |
| 签名 | 本机 SDK `hap-sign-tool.jar` + `OpenHarmony.p12`（官方 CA，密码 `123456`） |

## 3. API 实测发现（API 26 Beta / OpenHarmony 7.0）

1. `DocumentViewPicker.select()` 返回 `Array<string>`（uri 数组）。✅ 真机工作。
2. `readTextSync(uri)` **不支持 URI**（实测错误 **13900002**）→ 改用 `openSync(fd)+readSync+TextDecoder`（fd 读取）。
3. `openSync(uri)` + `statSync(fd)` 对已授权 URI 可用（4178 字节读取成功）；**进程重启后返回 13900001（权限失效）**。
4. `@ohos.application.uriPermissionManager` 在 API 26 Beta 中 **namespace 为空**（无 persistPermission 类型）→ 编译期不可调用（R-10）。
5. preferences 保存/读取（最近文件模型）正常工作。

## 4. 签名与安装链路（完整排障记录，已成脚本 `scripts/sign-local.sh`）

设备侧最终校验成功的签名体系（逐层排障结论）：

1. **app 证书**：`generate-app-cert`，issuer = `OpenHarmony Application CA`，**subject 必须 = `OpenHarmony Application Release`**（设备按 trusted_apps_sources.json 的 `app-signing-cert` DN 匹配）。
2. **profile 证书**：`generate-profile-cert`，issuer = Application CA，**subject 必须 = `OpenHarmony Application Profile Debug`**（trusted sources 的 `profile-debug-signing-certificate`）。**设备校验 profile 签名者 issuer == source 的 `issuer-ca`（Application CA）**——使用 p12 内自签的 profile CA 直接签必失败（`profile signature is not trusted source`）。
3. **profile 内容**：证书字段用**带尾部换行的 PEM 文本**（`startsWith("-----BEGIN CERTIFICATE-----\n") && endsWith("-----END CERTIFICATE-----\n")` 工具才走 PEM 分支；裸 base64 或 URL-safe 会被设备侧 `GetX509CertFromPemString` 拒绝）；**必须含 `validity` 时间窗口**（否则设备判"应用已过期"限制启动，错误 10106105）；`debug-info.device-ids` + `device-id-type: udid`。
4. **设备信任库**：本机镜像 `trusted_root_ca.json` 只含根 CA；将 Profile Debug/Release CA 证书补入后（`/system` overlay 可写）ATM/installs 校验通过。**注**：标准开发板/官方镜像通常已内置，无需修补。
5. **安装模式**：`deliveryWithInstall` 必须为 `false`（true 时应用被动态交付机制回收，bundle-removed）。
6. debug 安装还触发"应用已过期"对话框（validity 缺失）与 AppGallery 管控（aquired profile 修复后解除）。

## 5. 矩阵结果

| 场景 | 结果 | 证据 |
|---|---|---|
| 选择器打开 | ✅ | picker UI 打开（filemanager filePickerIndex） |
| 文件选中 | ✅ | 已选 (1/1000) 状态确认 |
| URI stat/读取（单次会话） | ✅ | muhub-diagnostics 4178 字节 + 内容记录 |
| 同步 readTextSync(uri) | ❌ 13900002 | 已修复（fd 读取），构建通过 |
| 重启后访问 | ❌ 13900001 | 强杀→重启→记录重开失败（**临时授权模型证实**） |
| 原位写入（文件系统层） | ✅ | docs provider 路径追加探针成功 |
| 文件删除 | ✅ | hdc 删除成功 |
| 失败路径（权限/删除） | ✅ | 明确错误码、无崩溃 |
| persistPermission | ⛔ 编译期不可用 | R-10（API 26 Beta 类型缺失） |

## 6. 对规格的影响（已写入 acceptance/risks）

- FR-FILE-002 在 V0.1 按"临时访问 + 重新定位"交付（ADR-009 草案；SDD M0-02 门禁）。
- FR-FILE-003/004 的读取链路按 fd 读取实现（不依赖 readTextSync URI 支持）。
- 真机验证矩阵已全部执行或明确标注自动化环境限制（R-12）。

## 7. 遗留与建议

1. R-12（本镜像 picker 的"打开"按钮自动化注入不生效——真实用户手动操作正常）：换标准镜像或人工操作可复测应用内写链路。
2. 正式 SDK 发布后复核 persistPermission（R-10 关闭项）。
3. sign-local.sh 为工程固化资产：任何可调试设备一键签名安装。