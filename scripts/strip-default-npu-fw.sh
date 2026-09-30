#!/usr/bin/env bash
# ==================================================================
# 把 stock NPU 固件包从 target 的 DEFAULT_PACKAGES / DEVICE_PACKAGES 里摘掉
#
# 为什么必须做：
#   airoha-en7581-npu-firmware 是 airoha/an7581 subtarget 的 DEFAULT_PACKAGE，
#   make defconfig 会把它拉回 =y。于是「ClankerNPU 可选插件包」和 stock 包
#   会同时被装进 rootfs，两个包装的是同一批文件名（/lib/firmware/airoha/
#   <prefix>_npu_{rv32,data}.bin），谁生效取决于安装顺序 —— 不可控。
#
#   摘掉 DEFAULT_PACKAGES 后，装不装、装哪个完全由 .config 里的
#   CONFIG_PACKAGE_xxx 决定，可选插件才真的「可选」。
#
#   注意：摘掉之后 stock 包符号依然存在，想用官方固件只要在 .config 里
#   显式写 CONFIG_PACKAGE_airoha-en7581-npu-firmware=y 即可（见 workflow 7.5）。
#
# 用法：
#   PONWRT_DIR=. ./scripts/strip-default-npu-fw.sh
# ==================================================================
set -euo pipefail

PONWRT_DIR="${PONWRT_DIR:-.}"
cd "$PONWRT_DIR"

# 要摘掉的包（linux-firmware 提供的官方 NPU 固件）
STRIP_RE='airoha-[A-Za-z0-9_.-]*npu-firmware'

mapfile -t FILES < <(grep -rlE "DEFAULT_PACKAGES|DEVICE_PACKAGES" target/ 2>/dev/null || true)

CHANGED=0
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  if ! grep -qE "$STRIP_RE" "$f"; then
    continue
  fi
  BEFORE="$(grep -nE "(DEFAULT_PACKAGES|DEVICE_PACKAGES).*${STRIP_RE}" "$f" || true)"
  # 只在含 DEFAULT_PACKAGES / DEVICE_PACKAGES 的行里删 token
  perl -i -pe "s{^(\s*(?:DEFAULT_PACKAGES|DEVICE_PACKAGES)\s*[+:!]?=.*)$}{my \$l=\$1; \$l =~ s/\s*$STRIP_RE\b//g; \$l}gme" "$f"
  AFTER="$(grep -nE "(DEFAULT_PACKAGES|DEVICE_PACKAGES).*${STRIP_RE}" "$f" || true)"
  if [ "$BEFORE" != "$AFTER" ]; then
    CHANGED=$((CHANGED + 1))
    echo "✅ 已从 $f 摘掉 stock NPU 固件包:"
    echo "$BEFORE" | sed 's/^/   - /'
  fi
done

if [ "$CHANGED" = "0" ]; then
  echo "ℹ 未发现 DEFAULT_PACKAGES / DEVICE_PACKAGES 里的 stock NPU 固件包（无需改动）"
else
  echo ">>> 共修改 $CHANGED 个文件；stock NPU 固件现在完全由 .config 决定"
fi
