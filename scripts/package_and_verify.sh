#!/usr/bin/env bash
# 把未签名的真机 arm64 .app 打成 IPA，并做静态检查。失败则拒绝打包。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${1:-$ROOT/build/MicroduckStudio.xcarchive}"
OUT_IPA="${2:-$ROOT/build/MicroduckStudio-unsigned.ipa}"
APP_NAME="MicroduckStudio.app"
EXPECT_BUNDLE_ID="com.viniedodo.microduck-studio"
EXPECT_EXEC="MicroduckStudio"

if [[ ! -d "$ARCHIVE" ]]; then
  echo "archive not found: $ARCHIVE" >&2
  exit 1
fi

APP="$ARCHIVE/Products/Applications/$APP_NAME"
if [[ ! -d "$APP" ]]; then
  echo "expected $APP" >&2
  find "$ARCHIVE" -name '*.app' -prune >&2 || true
  exit 1
fi

PLIST="$APP/Info.plist"
if [[ ! -f "$PLIST" ]]; then
  echo "missing Info.plist" >&2
  exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
EXEC="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$PLIST" 2>/dev/null || true)"
echo "CFBundleIdentifier=$BUNDLE_ID"
echo "CFBundleExecutable=$EXEC"
echo "MinimumOSVersion=${MIN_OS:-unknown}"

if [[ "$BUNDLE_ID" != "$EXPECT_BUNDLE_ID" ]]; then
  echo "unexpected bundle id: $BUNDLE_ID" >&2
  exit 1
fi
if [[ "$EXEC" != "$EXPECT_EXEC" ]]; then
  echo "unexpected executable: $EXEC" >&2
  exit 1
fi

BIN="$APP/$EXEC"
if [[ ! -f "$BIN" ]]; then
  echo "missing binary $BIN" >&2
  exit 1
fi

echo "file: $(file "$BIN")"
LIPO="$(lipo -info "$BIN" 2>&1 || true)"
echo "lipo: $LIPO"
if echo "$LIPO" | grep -Eqi 'x86_64|i386'; then
  echo "refusing binary that contains simulator/intel slices" >&2
  exit 1
fi
if ! echo "$LIPO" | grep -q 'arm64'; then
  echo "binary is not arm64" >&2
  exit 1
fi

# 必须是 iOS 真机平台，不能是模拟器。
if command -v vtool >/dev/null 2>&1; then
  VOUT="$(vtool -show "$BIN" 2>&1 || true)"
  echo "$VOUT"
  if echo "$VOUT" | grep -Eqi 'platform IOSSIMULATOR|platform 7|IOSSIMULATOR'; then
    echo "refusing iOS simulator binary" >&2
    exit 1
  fi
  if ! echo "$VOUT" | grep -Eqi 'platform IOS($| )|platform 2([^0-9]|$)'; then
    # vtool 常见输出：platform IOS  或  platform 2
    if ! echo "$VOUT" | grep -Eq 'platform IOS'; then
      echo "warning: could not confirm IOS platform from vtool; checking otool" >&2
    fi
  fi
fi

OTOOL="$(otool -l "$BIN" 2>/dev/null || true)"
if echo "$OTOOL" | grep -q 'platform 7'; then
  echo "refusing LC_BUILD_VERSION platform 7 (iOS simulator)" >&2
  exit 1
fi
# platform 2 = PLATFORM_IOS
if ! echo "$OTOOL" | grep -q 'platform 2'; then
  echo "$OTOOL" | grep -A4 LC_BUILD_VERSION || true
  echo "could not find LC_BUILD_VERSION platform 2 (iOS device)" >&2
  exit 1
fi

# 未签名，且不能夹带描述文件或证书。
if [[ -f "$APP/embedded.mobileprovision" ]]; then
  echo "refusing app that contains embedded.mobileprovision" >&2
  exit 1
fi
if find "$APP" -iname '*.mobileprovision' -o -iname 'embedded.provisionprofile' | grep -q .; then
  echo "refusing app that contains a provisioning profile" >&2
  exit 1
fi

CS_OUT="$(mktemp)"
set +e
codesign --verify --verbose=2 "$APP" >"$CS_OUT" 2>&1
CS_VERIFY=$?
set -e
codesign -dv --verbose=2 "$APP" >>"$CS_OUT" 2>&1 || true
cat "$CS_OUT"
if grep -Eqi 'Authority=|Signature size=|TeamIdentifier=' "$CS_OUT"; then
  echo "refusing signed app or leftover signing identity" >&2
  exit 1
fi
if ! grep -Eqi 'not signed at all|code object is not signed' "$CS_OUT"; then
  # 有的 Xcode 版本对未签名 app 的措辞不同；若 verify 成功则视为已签名，拒绝。
  if [[ $CS_VERIFY -eq 0 ]]; then
    echo "codesign --verify succeeded; refusing apparently signed app" >&2
    exit 1
  fi
  echo "warning: unsigned wording not found, but verify failed; continuing after listing output" >&2
fi

WORKDIR="$(mktemp -d)"
mkdir -p "$WORKDIR/Payload"
cp -a "$APP" "$WORKDIR/Payload/"
rm -f "$OUT_IPA"
(
  cd "$WORKDIR"
  # IPA 是 zip，根目录必须是 Payload/
  zip -r9 "$OUT_IPA" Payload
)
rm -rf "$WORKDIR"

echo "wrote $OUT_IPA"
echo "size=$(wc -c < "$OUT_IPA") bytes"
shasum -a 256 "$OUT_IPA"
echo "zip listing (first entries):"
unzip -Z1 "$OUT_IPA" | head -20
if ! unzip -Z1 "$OUT_IPA" | head -1 | grep -q '^Payload/'; then
  echo "IPA root is not Payload/" >&2
  exit 1
fi
if unzip -Z1 "$OUT_IPA" | grep -Eqi 'simulator|\.dSYM/'; then
  echo "IPA should not contain simulator slices or dSYMs" >&2
  exit 1
fi
echo "package_and_verify: OK"
