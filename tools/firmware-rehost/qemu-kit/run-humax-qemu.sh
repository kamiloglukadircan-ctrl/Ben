#!/usr/bin/env bash
# ==========================================================================
# Humax QEMU Kiti — MIPS big-endian sanal ortam + kurtarilan Humax parcalari
# ==========================================================================
# Calisan bir MIPS big-endian Linux ortamini (OpenWrt Malta — W9970 benzeri
# "donor") QEMU'da boot eder ve kurtardigimiz gercek Humax parcalarini
# (init scriptleri, binary'ler) icine bagli olarak sunar. Boot edince
# calisan bir MIPS Linux root kabugu + /mnt/humax altinda kurtarilan Humax
# icerigi olur — inceleyebilir, scriptleri calistirabilirsin.
#
# NOT: Bu tam Humax sistemi DEGIL (o temiz bir NAND dokumu ister). Bu,
# W9970 donor ortami + kurtardigimiz gercek Humax parcalari. QEMU'da
# calisir, senin makinende, sen kullanirsin.
#
# Kullanim (Lenovo/Linux):  ./run-humax-qemu.sh
# ==========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECOVERED="$SCRIPT_DIR/humax-recovered"
WORK="$SCRIPT_DIR/.qemu-work"
mkdir -p "$WORK"

KERNEL="$WORK/openwrt-malta-be-vmlinux-initramfs.elf"
KURL="https://downloads.openwrt.org/releases/23.05.5/targets/malta/be/openwrt-23.05.5-malta-be-vmlinux-initramfs.elf"

echo "=========================================="
echo " Humax QEMU Kiti"
echo "=========================================="

# --- 1. Bagimliliklar ---
if ! command -v qemu-system-mips >/dev/null 2>&1; then
    echo "[..] qemu-system-mips kuruluyor (sudo)..."
    sudo apt-get update -qq && sudo apt-get install -y -qq qemu-system-mips e2fsprogs wget
fi

# --- 2. Donor kernel indir (OpenWrt Malta big-endian) ---
if [[ ! -f "$KERNEL" ]]; then
    echo "[..] MIPS big-endian donor kernel indiriliyor..."
    if ! wget -q -O "$KERNEL" "$KURL"; then
        echo "[HATA] Kernel indirilemedi. Elle indir:"
        echo "   $KURL"
        echo "   -> kaydet: $KERNEL"
        exit 1
    fi
    echo "[OK] Kernel indirildi."
fi

# --- 3. Kurtarilan icerigi ext2 imajina koy (QEMU'ya baglamak icin) ---
IMG="$WORK/humax-recovered.ext2"
echo "[..] Kurtarilan Humax icerigi disk imajina yaziliyor..."
rm -f "$IMG"
dd if=/dev/zero of="$IMG" bs=1M count=64 2>/dev/null
if command -v mke2fs >/dev/null 2>&1; then
    mke2fs -q -F -t ext2 -d "$RECOVERED" "$IMG" 2>/dev/null || {
        mke2fs -q -F -t ext2 "$IMG"
        echo "[UYARI] -d desteklenmiyor; icerigi QEMU icinden elle kopyalaman gerekebilir."
    }
    echo "[OK] Disk imaji hazir: $IMG"
else
    echo "[UYARI] mke2fs yok; e2fsprogs kur."
fi

echo
echo "=========================================="
echo " QEMU BASLATILIYOR"
echo "=========================================="
echo " Boot bitince OpenWrt (MIPS big-endian) root kabugu gelir."
echo " Kurtarilan Humax icerigini gormek icin QEMU icinde:"
echo
echo "     mkdir -p /mnt/humax"
echo "     mount -t ext2 /dev/sda /mnt/humax"
echo "     ls -la /mnt/humax"
echo "     cat /mnt/humax/etc/inittab        # UART satirlarini gor"
echo "     cat /mnt/humax/etc/init.d/S90settop  # kanal DB mount'larini gor"
echo "     cat /mnt/humax/etc/passwd"
echo
echo " Cikis: QEMU'yu kapatmak icin  Ctrl-A sonra X"
echo "=========================================="
echo
sleep 2

exec qemu-system-mips \
    -M malta \
    -m 256 \
    -kernel "$KERNEL" \
    -drive file="$IMG",format=raw,if=ide \
    -nographic \
    -append "console=ttyS0 rootwait"
