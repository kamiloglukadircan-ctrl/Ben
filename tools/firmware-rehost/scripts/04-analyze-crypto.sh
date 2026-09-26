#!/usr/bin/env bash
# ==========================================================================
# Adım 4: Kriptografi ve Güvenlik Analizi
# ==========================================================================
# Çıkarılmış rootfs üzerinde (chroot gerekmeden, doğrudan Mac'ten):
#   - AES/şifreleme kütüphanelerini bulur
#   - Init script'lerini analiz eder
#   - Gömülü anahtarları/sertifikaları arar
#   - Binary'lerdeki kriptografi ipuçlarını tarar
#
# Kullanım: ./04-analyze-crypto.sh ../config/humax-5000s.env
# ==========================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
require_config "${1:-}"

# --- Rootfs'i bul ---
ROOTFS_DIR=""
for candidate in "$EXTRACT_DIR/rootfs" "$EXTRACT_DIR"/*/squashfs-root; do
    if [[ -d "$candidate" && ( -d "$candidate/bin" || -d "$candidate/etc" ) ]]; then
        ROOTFS_DIR="$candidate"
        break
    fi
done

if [[ -z "$ROOTFS_DIR" ]]; then
    log_error "RootFS dizini bulunamadı. Önce 02-extract-rootfs.sh çalıştır."
    exit 1
fi

REPORT="$EXTRACT_DIR/crypto-analysis-report.txt"
log_info "Cihaz: $DEVICE_NAME"
log_info "RootFS: $ROOTFS_DIR"
log_info "Rapor: $REPORT"
echo

{
echo "================================================================"
echo " KRİPTOGRAFİ VE GÜVENLİK ANALİZ RAPORU"
echo " Cihaz: $DEVICE_NAME"
echo " Tarih: $(date '+%Y-%m-%d %H:%M:%S')"
echo " RootFS: $ROOTFS_DIR"
echo "================================================================"
echo

# --- 1. Paylaşımlı Kütüphaneler (.so) ---
echo "================================================================"
echo " 1. PAYLAŞIMLI KÜTÜPHANELER"
echo "================================================================"
echo
echo "--- Kriptografi ile ilişkili .so dosyaları ---"
find "$ROOTFS_DIR" -name "*.so*" 2>/dev/null | while read -r sofile; do
    basename_so=$(basename "$sofile")
    for pat in crypto ssl aes des cipher cas crypt; do
        if echo "$basename_so" | grep -qi "$pat"; then
            size=$(stat -f%z "$sofile" 2>/dev/null || stat -c%s "$sofile" 2>/dev/null)
            echo "  $(human_size "$size")  $sofile"
            break
        fi
    done
done
echo
echo "--- Tüm .so dosyaları ---"
find "$ROOTFS_DIR" -name "*.so*" 2>/dev/null | sort
echo

# --- 2. Çalıştırılabilir Dosyalar (Binary) ---
echo "================================================================"
echo " 2. ŞİFRELEME İLE İLİŞKİLİ BINARY'LER"
echo "================================================================"
echo
for pat in ${CRYPTO_PATTERNS:-aes AES openssl encrypt decrypt}; do
    MATCHES=$(find "$ROOTFS_DIR" -type f -executable 2>/dev/null | xargs grep -rl "$pat" 2>/dev/null || true)
    if [[ -n "$MATCHES" ]]; then
        echo "--- '$pat' içeren çalıştırılabilir dosyalar ---"
        echo "$MATCHES" | while read -r f; do
            echo "  $f"
        done
        echo
    fi
done

# strings ile derin tarama
echo "--- Binary'lerde bulunan kriptografi string'leri ---"
find "$ROOTFS_DIR" -type f \( -executable -o -name "*.so*" \) 2>/dev/null | while read -r binfile; do
    CRYPTO_STRINGS=$(strings "$binfile" 2>/dev/null | grep -iE "(aes|AES|encrypt|decrypt|cipher|HMAC|sha256|openssl|RSA|private.key|-----BEGIN)" | head -5)
    if [[ -n "$CRYPTO_STRINGS" ]]; then
        echo
        echo "  [$binfile]"
        echo "$CRYPTO_STRINGS" | sed 's/^/    /'
    fi
done
echo

# --- 3. Init Script'leri ---
echo "================================================================"
echo " 3. BAŞLATMA BETİKLERİ (${INIT_SCRIPT_DIR:-/etc/init.d})"
echo "================================================================"
echo
INIT_DIR="$ROOTFS_DIR${INIT_SCRIPT_DIR:-/etc/init.d}"
if [[ -d "$INIT_DIR" ]]; then
    echo "--- Mevcut init script'leri ---"
    ls -la "$INIT_DIR" 2>/dev/null
    echo
    echo "--- Kriptografi/güvenlik referansları içeren script'ler ---"
    for f in "$INIT_DIR"/*; do
        [[ -f "$f" ]] || continue
        HITS=$(grep -liE "(crypt|ssl|key|cert|cas|secure|auth|password|token|aes)" "$f" 2>/dev/null || true)
        if [[ -n "$HITS" ]]; then
            echo
            echo "  [$f]"
            grep -niE "(crypt|ssl|key|cert|cas|secure|auth|password|token|aes)" "$f" 2>/dev/null | head -10 | sed 's/^/    /'
        fi
    done
else
    echo "  Init dizini bulunamadı: $INIT_DIR"
fi
echo

# --- 4. Sertifikalar ve Anahtar Dosyaları ---
echo "================================================================"
echo " 4. SERTİFİKALAR VE ANAHTAR DOSYALARI"
echo "================================================================"
echo
echo "--- PEM/DER/CRT/KEY dosyaları ---"
find "$ROOTFS_DIR" -type f \( -name "*.pem" -o -name "*.crt" -o -name "*.key" \
    -o -name "*.der" -o -name "*.p12" -o -name "*.pfx" -o -name "*.cer" \
    -o -name "*.cert" \) 2>/dev/null | while read -r certfile; do
    size=$(stat -f%z "$certfile" 2>/dev/null || stat -c%s "$certfile" 2>/dev/null)
    echo "  $(human_size "$size")  $certfile"
done
echo
echo "--- Gömülü sertifika/anahtar blokları (binary'ler içinde) ---"
find "$ROOTFS_DIR" -type f -size +1k 2>/dev/null | while read -r f; do
    if strings "$f" 2>/dev/null | grep -q "-----BEGIN"; then
        echo "  $f"
        strings "$f" 2>/dev/null | grep "-----BEGIN" | head -3 | sed 's/^/    /'
    fi
done
echo

# --- 5. Config Dosyaları ---
echo "================================================================"
echo " 5. İLGİNÇ CONFIG DOSYALARI"
echo "================================================================"
echo
echo "--- /etc/ altındaki config dosyaları ---"
find "$ROOTFS_DIR/etc" -type f 2>/dev/null | sort | while read -r cfg; do
    # Şifreleme/güvenlik referansı içerenleri işaretle
    if grep -qlE "(password|secret|key|token|crypt|auth)" "$cfg" 2>/dev/null; then
        echo "  [!] $cfg"
    fi
done
echo

# --- 6. /dev/ Device Node'ları ---
echo "================================================================"
echo " 6. ÖZEL DEVICE NODE'LARI (/dev/)"
echo "================================================================"
echo
echo "--- Donanıma bağlı device'lar (QEMU'da çalışmaz) ---"
find "$ROOTFS_DIR/dev" -type c -o -type b 2>/dev/null | while read -r devnode; do
    echo "  $devnode"
done
if [[ -d "$ROOTFS_DIR/etc/udev" ]]; then
    echo
    echo "--- udev kuralları ---"
    find "$ROOTFS_DIR/etc/udev" -name "*.rules" 2>/dev/null | while read -r rule; do
        echo "  $rule"
    done
fi
echo

# --- 7. Kullanıcı Hesapları ---
echo "================================================================"
echo " 7. KULLANICI HESAPLARI"
echo "================================================================"
echo
if [[ -f "$ROOTFS_DIR/etc/passwd" ]]; then
    echo "--- /etc/passwd ---"
    cat "$ROOTFS_DIR/etc/passwd"
    echo
fi
if [[ -f "$ROOTFS_DIR/etc/shadow" ]]; then
    echo "--- /etc/shadow (hash'ler) ---"
    cat "$ROOTFS_DIR/etc/shadow"
    echo
fi
echo

# --- 8. Firmware Güncelleme Mekanizması ---
echo "================================================================"
echo " 8. FİRMWARE GÜNCELLEME MEKANİZMASI"
echo "================================================================"
echo
echo "--- Güncelleme ile ilişkili dosyalar ---"
find "$ROOTFS_DIR" -type f \( -name "*update*" -o -name "*upgrade*" \
    -o -name "*ota*" -o -name "*fwup*" -o -name "*flash*" \) 2>/dev/null | while read -r updfile; do
    echo "  $updfile"
done
echo
echo "--- Güncelleme URL'leri / sunucu referansları ---"
find "$ROOTFS_DIR" -type f -size -100k 2>/dev/null | xargs grep -rlE "(http://|https://|ftp://)" 2>/dev/null | while read -r f; do
    URLS=$(grep -ohE "(http|https|ftp)://[^ \"'<>]+" "$f" 2>/dev/null | sort -u | head -5)
    if [[ -n "$URLS" ]]; then
        echo "  [$f]"
        echo "$URLS" | sed 's/^/    /'
        echo
    fi
done

echo
echo "================================================================"
echo " RAPOR SONU"
echo "================================================================"

} | tee "$REPORT"

echo
log_ok "Analiz raporu kaydedildi: $REPORT"
log_ok "Chroot ortamında canlı test için: 03-qemu-rehost.sh"
