#!/usr/bin/env bash
# ==========================================================================
# Adım 7: firmware-mod-kit ile SquashFS Çıkarma (son çare)
# ==========================================================================
# sasquatch tek bir unsquashfs varyantidir ve Broadcom'un standart-disi
# superblock'unu (block_log/version alanlari kaymis) acamadi. firmware-mod-kit
# ~20 farkli unsquashfs binary'si icerir (2.x, 3.x, 4.x, LZMA'li, Broadcom,
# Realtek, Cisco varyantlari) ve unsquashfs_all.sh hepsini sirayla dener.
#
# Kullanim: ./07-extract-fmk.sh <rootfs.sqfs> [cikti-dizini]
# Ornek:    ./07-extract-fmk.sh ~/firmware-analysis/rootfs.sqfs
# ==========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

SQFS_FILE="${1:-}"
OUT_DIR="${2:-}"

if [[ -z "$SQFS_FILE" || ! -f "$SQFS_FILE" ]]; then
    log_error "SquashFS dosyasi bulunamadi: ${SQFS_FILE:-<verilmedi>}"
    echo "Kullanim: $0 <rootfs.sqfs> [cikti-dizini]" >&2
    exit 1
fi

FMK_DIR="${FMK_DIR:-$HOME/firmware-mod-kit}"

# --- Bagimliliklar (sasquatch ile ayni) ---
log_info "Bagimliliklar kontrol ediliyor..."
sudo apt-get install -y -qq build-essential zlib1g-dev liblzma-dev \
    liblzo2-dev libattr1-dev git >/dev/null 2>&1 || true

# --- fmk klonla + derle ---
if [[ ! -d "$FMK_DIR" ]]; then
    log_info "firmware-mod-kit klonlaniyor: $FMK_DIR"
    git clone --depth 1 https://github.com/rampageX/firmware-mod-kit.git "$FMK_DIR"
fi

if [[ ! -f "$FMK_DIR/src/squashfs-3.0/unsquashfs" ]]; then
    log_info "firmware-mod-kit derleniyor (birkac dakika surebilir)..."
    ( cd "$FMK_DIR/src" && make >/dev/null 2>&1 ) || {
        log_warn "make bazi hedeflerde uyari verdi (normal) — unsquashfs binary'leri kontrol ediliyor."
    }
fi

BUILT=$(find "$FMK_DIR/src" -name "unsquashfs*" -type f -executable 2>/dev/null | wc -l)
if (( BUILT == 0 )); then
    log_error "Hicbir unsquashfs varyanti derlenemedi. $FMK_DIR/src icinde 'make' ciktisini kontrol et."
    exit 1
fi
log_ok "$BUILT adet unsquashfs varyanti hazir."
echo

# --- unsquashfs_all.sh ile tum varyantlari dene ---
log_info "Tum unsquashfs varyantlari deneniyor (unsquashfs_all.sh)..."
log_info "SquashFS: $SQFS_FILE"
echo

cd "$FMK_DIR"
if [[ -n "$OUT_DIR" ]]; then
    ./unsquashfs_all.sh "$SQFS_FILE" "$OUT_DIR" 2>&1 | tee /tmp/fmk-extract.log
else
    ./unsquashfs_all.sh "$SQFS_FILE" 2>&1 | tee /tmp/fmk-extract.log
fi

echo
echo "=========================================="
# --- Sonuc kontrolu ---
RESULT_DIR=$(find "$(dirname "$SQFS_FILE")" "$FMK_DIR" -maxdepth 3 -type d \
    \( -name "squashfs-root*" -o -name "*.extracted" \) 2>/dev/null | head -1)

if [[ -n "$RESULT_DIR" ]] && [[ -d "$RESULT_DIR/bin" || -d "$RESULT_DIR/etc" || -d "$RESULT_DIR/usr" ]]; then
    log_ok "BASARILI! RootFS cikarildi: $RESULT_DIR"
    echo
    ls -la "$RESULT_DIR"
    echo
    echo "Temel dizinler:"
    for d in bin sbin etc lib usr var opt app; do
        [[ -d "$RESULT_DIR/$d" ]] && echo "  + /$d"
    done
else
    log_warn "Hicbir varyant basarili olamadi."
    echo "unsquashfs_all.sh ciktisi: /tmp/fmk-extract.log" >&2
    echo >&2
    echo "Sonraki secenek: Humax/BCM7358 GPL kaynak kodundaki kendi unsquashfs'i." >&2
    echo "Bu box'in uretici GPL surumunu ara (Humax open source sayfasi)." >&2
fi
