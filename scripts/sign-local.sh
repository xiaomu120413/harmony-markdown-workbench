#!/usr/bin/env bash
# M0-02 本地签名脚本：为 Debug HAP 生成 OpenHarmony 官方 CA 签名的安装包。
#
# 背景（docs/spikes/external-uri.md、R-10/R-11）：
# - hvigor 6 的 signingConfigs 密码是 IDE 加密格式，不适合脚本化；本脚本绕开 hvigor，
#   直接使用 SDK 的 hap-sign-tool + OpenHarmony 官方调试 CA（DevEco 内置）签名。
# - profile p7b 用 openssl cms -nodetach 生成（hap-sign-tool 对自签 CA 链有行为限制，
#   见脚本内注释），由 OpenHarmony Application Profile Debug CA 签发。
#
# 用法：
#   bash scripts/sign-local.sh <unsigned.hap> [输出路径] [UDID] [bundleName]
# 默认输出到工程外 ../local-sign/entry-signed-local.hap。
# 材料目录：../local-sign/（工程外，不入库；README「签名说明」章节）。
# 需要：DevEco Studio 完整安装（SDK toolchains）、openssl、Node/Python 可用。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BASE_DIR="$(cd "${ROOT}/.." && pwd)/local-sign"

IN_HAP="${1:-${ROOT}/entry/build/default/outputs/default/entry-default-unsigned.hap}"
OUT_HAP="${2:-${BASE_DIR}/entry-signed-local.hap}"
UDID="${3:-$(hdc list targets 2>/dev/null | head -1 | tr -d '[:space:]')}"
BUNDLE_NAME="${4:-com.markdownworkbench.app}"

TOOLCHAINS='/c/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains'
HAP_SIGN_TOOL="${TOOLCHAINS}/lib/hap-sign-tool.jar"
OH_P12="${TOOLCHAINS}/lib/OpenHarmony.p12"
OH_P12_PASS='123456'

KEYSTORE="${BASE_DIR}/hmwb-local.p12"
KEY_ALIAS='hmwb-local'
KEY_PASS='hmwb123456'

mkdir -p "${BASE_DIR}"

echo "[sign-local] 检查材料目录: ${BASE_DIR}"
if [ ! -f "${KEYSTORE}" ]; then
  echo "[sign-local] 生成应用密钥对（EC secp256r1）"
  openssl ecparam -genkey -name prime256v1 -noout -out "${BASE_DIR}/leaf.key"
  printf "keyUsage=critical,digitalSignature\nextendedKeyUsage=codeSigning\n" > "${BASE_DIR}/leaf.ext"
  openssl req -new -key "${BASE_DIR}/leaf.key" -out "${BASE_DIR}/leaf.csr" \
    -subj "/CN=HMWB Local Dev/O=MarkdownWorkbench/C=CN"
  openssl x509 -req -in "${BASE_DIR}/leaf.csr" -signkey "${BASE_DIR}/leaf.key" \
    -out "${BASE_DIR}/leaf-tmp.cer" -days 3650 -sha256 -extfile "${BASE_DIR}/leaf.ext"
  # 用占位自签证书初始化 p12（随后 generate-app-cert 会以官方 CA 覆盖证书链）
  openssl pkcs12 -export -inkey "${BASE_DIR}/leaf.key" -in "${BASE_DIR}/leaf-tmp.cer" \
    -name "${KEY_ALIAS}" -out "${KEYSTORE}" -passout pass:"${KEY_PASS}"
  rm -f "${BASE_DIR}/leaf-tmp.cer"
fi

if [ ! -f "${BASE_DIR}/app.certChain.cer" ]; then
  echo "[sign-local] 导出 OpenHarmony 官方 CA 证书"
  openssl pkcs12 -legacy -in "${OH_P12}" -passin pass:"${OH_P12_PASS}" -nokeys -out "${BASE_DIR}/ca-all.pem" 2>/dev/null
  python - "${BASE_DIR}" <<'PYEOF'
import re, sys
base = sys.argv[1]
pem = open(f'{base}/ca-all.pem', encoding='utf-8').read()
blocks = re.findall(r'(subject=[^\n]*\n.*?-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----)', pem, re.S)
need = {
    'openharmony application ca': 'app-ca.cer',
    'openharmony application profile debug': 'profile-debug-ca.cer',
    'openharmony application root ca': 'root-ca.cer',
}
got = {}
for b in blocks:
    subj = b.split('\n')[0].lower()
    for key in need:
        if key in subj and key not in got:
            cert = re.search(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', b, re.S).group(0)
            got[key] = cert
for key, cert in got.items():
    open(f'{base}/{need[key]}', 'w').write(cert + '\n')
root = got.get('openharmony application root ca', '')
if root:
    open(f'{base}/root-ca.cer', 'w').write(root + '\n')
print('exported:', list(got.keys()))
PYEOF
  echo "[sign-local] 用官方 Application CA 签发应用证书"
  java -jar "${HAP_SIGN_TOOL}" generate-app-cert \
    -keyAlias "${KEY_ALIAS}" -keyPwd "${KEY_PASS}" \
    -issuer 'C=CN, O=OpenHarmony, OU=OpenHarmony Team, CN=OpenHarmony Application CA' \
    -issuerKeyAlias 'openharmony application ca' -issuerKeyPwd "${OH_P12_PASS}" \
    -issuerKeystoreFile "${OH_P12}" -issuerKeystorePwd "${OH_P12_PASS}" \
    -subject 'C=CN, O=MarkdownWorkbench, OU=Dev, CN=HMWB App' \
    -validity 3650 -signAlg SHA256withECDSA \
    -keystoreFile "${KEYSTORE}" -keystorePwd "${KEY_PASS}" \
    -outForm certChain -rootCaCertFile "${BASE_DIR}/root-ca.cer" -subCaCertFile "${BASE_DIR}/app-ca.cer" \
    -outFile "${BASE_DIR}/app.certChain.cer"
fi

if [ ! -f "${BASE_DIR}/profile-debug.key" ]; then
  echo "[sign-local] 导出 OpenHarmony Profile Debug 私钥"
  openssl pkcs12 -legacy -in "${OH_P12}" -passin pass:"${OH_P12_PASS}" -nodes -out "${BASE_DIR}/oh-all.pem" 2>/dev/null
  python - "${BASE_DIR}" <<'PYEOF'
import re, sys
base = sys.argv[1]
pem = open(f'{base}/oh-all.pem', encoding='utf-8').read()
for seg in re.split(r'(?=Bag Attributes)', pem):
    if 'friendlyName: openharmony application profile debug' in seg:
        key = re.search(r'-----BEGIN PRIVATE KEY-----.*?-----END PRIVATE KEY-----', seg, re.S)
        open(f'{base}/profile-debug.key', 'w').write(key.group(0) + '\n')
        print('profile-debug.key exported')
        break
PYEOF
fi

echo "[sign-local] 生成 profile.json（官方 UnsgnedDebugProfileTemplate 结构）"
python - "${BASE_DIR}" "${UDID}" "${BUNDLE_NAME}" <<'PYEOF'
import json, re, sys, uuid
base, udid, bundle = sys.argv[1], sys.argv[2], sys.argv[3]
chain = open(f'{base}/app.certChain.cer', encoding='utf-8').read()
first = chain.split('-----END CERTIFICATE-----')[0] + '-----END CERTIFICATE-----'
b64 = re.sub(r'-----BEGIN CERTIFICATE-----|-----END CERTIFICATE-----|\s', '', first)
b64url = b64.replace('+', '-').replace('/', '_')  # URL-safe base64（关键，普通 base64 会被拒）
profile = {
    'version-name': '2.0.0',
    'version-code': 2,
    'uuid': str(uuid.uuid4()),
    'type': 'debug',
    'bundle-info': {
        'developer-id': 'OpenHarmony',
        'development-certificate': b64url,
        'bundle-name': bundle,
        'apl': 'normal',
        'app-feature': 'hos_normal_app'
    },
    'debug-info': {
        'device-ids': [udid],
        'device-id-type': 'udid'
    },
    'issuer': 'pki_internal'
}
with open(f'{base}/profile-local.json', 'w', encoding='utf-8') as f:
    json.dump(profile, f, indent=2, ensure_ascii=False)
print('profile-local.json written for udid:', udid)
PYEOF

echo "[sign-local] 签名 profile（openssl cms，-nodetach 内嵌 content 为必需）"
openssl cms -sign -binary -nodetach \
  -in "${BASE_DIR}/profile-local.json" \
  -signer "${BASE_DIR}/profile-debug-ca.cer" \
  -inkey "${BASE_DIR}/profile-debug.key" \
  -outform DER -out "${BASE_DIR}/profile-local.p7b" \
  -md sha256 -nosmimecap

echo "[sign-local] 签名 HAP"
java -jar "${HAP_SIGN_TOOL}" sign-app \
  -mode localSign -keyAlias "${KEY_ALIAS}" -keyPwd "${KEY_PASS}" \
  -signAlg SHA256withECDSA \
  -appCertFile "${BASE_DIR}/app.certChain.cer" \
  -profileFile "${BASE_DIR}/profile-local.p7b" \
  -keystoreFile "${KEYSTORE}" -keystorePwd "${KEY_PASS}" \
  -inFile "${IN_HAP}" -outFile "${OUT_HAP}"

echo "[sign-local] 完成: ${OUT_HAP}"
ls -la "${OUT_HAP}"