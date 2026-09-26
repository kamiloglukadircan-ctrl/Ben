#!/usr/bin/env bash
# ==========================================================================
# Adım 6: sasquatch'i Linux'ta Derle (Linux Mint / Ubuntu / Debian)
# ==========================================================================
# Broadcom modifiye SquashFS formatlarini acmak icin gereken sasquatch
# aracini gercek Linux'ta derler. macOS'ta ayni derleme 9 farkli
# portabilite sorunuyla (sysinfo.h, sysmacros.h, FNM_EXTMATCH, sysctl,
# sigwaitinfo, xattr API farki, -Werror, -fcommon...) karsilasiyordu -
# Linux'ta bunlarin HICBIRI yok, sadece 2 kucuk derleyici bayragi yeterli.
#
# Kullanim: ./06-build-sasquatch-linux.sh [hedef-dizin]
# Varsayilan hedef: /usr/local/bin/sasquatch
# ==========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"

INSTALL_DIR="${1:-/usr/local/bin}"
BUILD_DIR="$(mktemp -d /tmp/sasquatch-build.XXXXXX)"

log_info "Build dizini: $BUILD_DIR"
log_info "Kurulum hedefi: $INSTALL_DIR/sasquatch"
echo

# --- Bagimliliklar ---
log_info "Bagimliliklar kuruluyor (sudo istenebilir)..."
sudo apt-get update -qq
sudo apt-get install -y -qq build-essential wget zlib1g-dev liblzma-dev \
    liblzo2-dev libattr1-dev git
log_ok "Bagimliliklar hazir."
echo

# --- Klonla ---
log_info "sasquatch klonlaniyor..."
git clone --quiet https://github.com/devttys0/sasquatch "$BUILD_DIR"
log_ok "Klonlandi: $BUILD_DIR"
echo

# --- Derle (build.sh once squashfs4.3'u indirir ve yamalar) ---
log_info "build.sh calistiriliyor (squashfs4.3 indirilip Broadcom yamasi uygulanacak)..."
cd "$BUILD_DIR"
./build.sh || true   # ilk derleme -Werror yuzunden basarisiz olacak, bu beklenen

SQFS_DIR="$BUILD_DIR/squashfs4.3/squashfs-tools"
if [[ ! -f "$SQFS_DIR/Makefile" ]]; then
    log_error "squashfs4.3 indirilemedi veya yamalanamadi. Build dizinini kontrol et: $BUILD_DIR"
    exit 1
fi

# --- Modern GCC/Clang uyumluluk yamalari ---
log_info "Modern derleyici uyumluluk yamalari uygulaniyor..."
cd "$SQFS_DIR"

# -Werror kaldir: eski koddaki onemsiz uyarilar (misleading-indentation,
# self-assign, dangling-pointer) modern derleyicide hataya donusuyor.
sed -i 's/-Werror//' Makefile

# -fcommon ekle: GCC 10+ varsayilan olarak -fno-common kullanir, bu da
# error.h'deki "int verbose;" gibi tentative tanimlari "multiple definition"
# link hatasina cevirir. -fcommon eski (GCC<10) davranisi geri getirir.
sed -i 's/^CFLAGS ?= -g -O2/CFLAGS ?= -g -O2 -fcommon/' Makefile

log_ok "Yamalar uygulandi: -Werror kaldirildi, -fcommon eklendi."
echo

# --- Temiz derleme ---
log_info "Temiz derleme baslatiliyor..."
make clean >/dev/null 2>&1 || true
if make 2>&1 | tail -20; then
    log_ok "Derleme basarili!"
else
    log_error "Derleme basarisiz. Yukaridaki hatalari kontrol et."
    exit 1
fi
echo

# --- Kur ---
if [[ -f "$SQFS_DIR/sasquatch" ]]; then
    log_info "sasquatch $INSTALL_DIR'a kopyalaniyor..."
    sudo cp "$SQFS_DIR/sasquatch" "$INSTALL_DIR/sasquatch"
    sudo chmod +x "$INSTALL_DIR/sasquatch"
    log_ok "Kuruldu: $INSTALL_DIR/sasquatch"
    echo
    "$INSTALL_DIR/sasquatch" -help 2>&1 | head -5
    echo
    log_ok "Kullanima hazir. Ornek:"
    echo "  sasquatch -d rootfs rootfs.sqfs"
else
    log_error "sasquatch binary'si bulunamadi: $SQFS_DIR/sasquatch"
    exit 1
fi
