#!/usr/bin/env bash
# ==========================================================================
# Adım 0: Mac Kurulum Script'i
# ==========================================================================
# Mac terminalinde çalıştır. Tüm gerekli araçları kurar ve dizin yapısını
# oluşturur. Tek seferde kopyala-yapıştır yap.
#
# Kullanım: bash 00-mac-setup.sh
# ==========================================================================
set -euo pipefail

echo "=========================================="
echo " Firmware Rehosting — Mac Kurulum"
echo "=========================================="
echo

# --- Homebrew kontrolü ---
if ! command -v brew >/dev/null 2>&1; then
    echo "[HATA] Homebrew bulunamadı. Önce kur:"
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
fi
echo "[OK] Homebrew mevcut"

# --- Araçları kur ---
TOOLS=(binwalk qemu squashfs)
for tool in "${TOOLS[@]}"; do
    if brew list "$tool" &>/dev/null; then
        echo "[OK] $tool zaten kurulu"
    else
        echo "[..] $tool kuruluyor..."
        brew install "$tool"
        echo "[OK] $tool kuruldu"
    fi
done

# --- Python bağımlılıkları (binwalk eklentileri) ---
if command -v pip3 >/dev/null 2>&1; then
    pip3 install pycryptodome entropy 2>/dev/null || true
    echo "[OK] Python eklentileri kuruldu"
fi

# --- Dizin yapısını oluştur ---
mkdir -p ~/firmware-dumps
mkdir -p ~/firmware-analysis/humax-5000s
mkdir -p ~/firmware-analysis/kernels
echo "[OK] Dizinler oluşturuldu:"
echo "     ~/firmware-dumps/           <- NAND dökümünü buraya koy"
echo "     ~/firmware-analysis/        <- çıktılar buraya gelecek"

# --- Donor kernel indir (OpenWrt Malta MIPS big-endian) ---
KERNEL_PATH="$HOME/firmware-analysis/kernels/openwrt-malta-be-vmlinux-initramfs.elf"
if [[ -f "$KERNEL_PATH" ]]; then
    echo "[OK] Donor kernel zaten mevcut: $KERNEL_PATH"
else
    echo "[..] OpenWrt Malta MIPS kernel indiriliyor (donor kernel)..."
    echo "     Bu Humax'ın kendi kernel'i değil — QEMU'da boot etmek için kullanacağız."
    curl -L -o "$KERNEL_PATH" \
        "https://downloads.openwrt.org/releases/23.05.5/targets/malta/be/openwrt-23.05.5-malta-be-vmlinux-initramfs.elf" \
        2>&1 || {
        echo "[UYARI] İndirme başarısız. Manuel indir:"
        echo "  https://downloads.openwrt.org/releases/23.05.5/targets/malta/be/"
        echo "  Dosya: openwrt-23.05.5-malta-be-vmlinux-initramfs.elf"
        echo "  Kaydet: $KERNEL_PATH"
    }
    if [[ -f "$KERNEL_PATH" ]]; then
        echo "[OK] Donor kernel indirildi: $KERNEL_PATH"
    fi
fi

echo
echo "=========================================="
echo " KURULUM TAMAM"
echo "=========================================="
echo
echo " Sonraki adımlar:"
echo
echo " 1) NAND dökümünü kopyala:"
echo "    cp /path/to/S34ML01G200BHI00@BGA63_2147.BIN ~/firmware-dumps/"
echo
echo " 2) Repo'yu klonla (henüz yapmadıysan):"
echo "    git clone https://github.com/kamiloglukadircan-ctrl/Ben.git"
echo "    cd Ben"
echo
echo " 3) Analizi başlat:"
echo "    cd tools/firmware-rehost"
echo "    ./scripts/01-nand-analyze.sh config/humax-5000s.env"
echo
