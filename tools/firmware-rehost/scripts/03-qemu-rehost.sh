#!/usr/bin/env bash
# ==========================================================================
# Adım 3: QEMU Firmware Rehosting (Frankenstein Laboratuvarı)
# ==========================================================================
# OpenWrt Malta MIPS kernel'ini QEMU'da boot eder, Humax rootfs'ini
# bağlayıp chroot ile "Alien Kernel" emülasyonu başlatır.
#
# Ne çalışır:  OS omurgası, dosya sistemi, shell, yazılımsal kriptografi
# Ne çalışmaz: MPEG dekoder, HDMI, DVB-S2 tuner, TV GUI (donanımsal)
#
# Kullanım: ./03-qemu-rehost.sh ../config/humax-5000s.env
#
# Ön koşullar:
#   - 02-extract-rootfs.sh çalıştırılmış ve rootfs çıkarılmış olmalı
#   - Donor kernel indirilmiş olmalı (config'teki DONOR_KERNEL_PATH)
#   - QEMU kurulu olmalı (brew install qemu / apt install qemu-system-mips)
# ==========================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
require_config "${1:-}"

QEMU_BIN="qemu-system-${DONOR_ARCH:-mips}"
require_tool "$QEMU_BIN"

# --- Rootfs'i bul ---
ROOTFS_DIR=""
if [[ -d "$EXTRACT_DIR/rootfs" ]]; then
    ROOTFS_DIR="$EXTRACT_DIR/rootfs"
else
    while IFS= read -r -d '' candidate; do
        if [[ -d "${candidate}/bin" || -d "${candidate}/etc" ]]; then
            ROOTFS_DIR="$candidate"
            break
        fi
    done < <(find "$EXTRACT_DIR" -type d -name "squashfs-root" -print0 2>/dev/null)
fi

if [[ -z "$ROOTFS_DIR" || ! -d "$ROOTFS_DIR" ]]; then
    log_error "RootFS dizini bulunamadı: $EXTRACT_DIR"
    echo "Önce 02-extract-rootfs.sh çalıştır." >&2
    exit 1
fi

# --- Donor kernel kontrolü ---
if [[ ! -f "${DONOR_KERNEL_PATH:-}" ]]; then
    log_error "Donor kernel bulunamadı: ${DONOR_KERNEL_PATH:-<ayarlanmamış>}"
    echo >&2
    echo "OpenWrt Malta MIPS big-endian kernel'i indir:" >&2
    echo "  mkdir -p \$(dirname '$DONOR_KERNEL_PATH')" >&2
    echo "  curl -L -o '$DONOR_KERNEL_PATH' \\" >&2
    echo "    'https://downloads.openwrt.org/releases/23.05.5/targets/malta/be/openwrt-23.05.5-malta-be-vmlinux-initramfs.elf'" >&2
    exit 1
fi

log_info "Cihaz:       $DEVICE_NAME"
log_info "SoC:         ${DEVICE_SOC:-bilinmiyor} (${DONOR_ARCH:-mips})"
log_info "Donor Kernel:$DONOR_KERNEL_PATH"
log_info "Humax RootFS:$ROOTFS_DIR"
log_info "QEMU:        $QEMU_BIN -M ${QEMU_MACHINE:-malta} -m ${QEMU_MEMORY:-256}"
echo

# --- Rootfs'i ext4 disk imajına dönüştür (QEMU'ya bağlamak için) ---
DISK_IMG="$EXTRACT_DIR/humax-rootfs.img"
DISK_SIZE="512M"

log_info "Humax rootfs'ini disk imajına dönüştürüyorum ($DISK_SIZE)..."

if [[ -f "$DISK_IMG" ]]; then
    log_info "Mevcut disk imajı bulundu, üzerine yazılacak."
fi

# macOS'ta mkfs.ext4 yoksa basit tarball yaklaşımı kullan
if command -v mkfs.ext4 >/dev/null 2>&1; then
    dd if=/dev/zero of="$DISK_IMG" bs=1M count=512 2>/dev/null
    mkfs.ext4 -F -d "$ROOTFS_DIR" "$DISK_IMG" 2>/dev/null || {
        mkfs.ext4 -F "$DISK_IMG" 2>/dev/null
        log_warn "mkfs.ext4 -d desteklenmiyor — rootfs'i QEMU içinden kopyalaman gerekecek."
    }
    log_ok "Disk imajı oluşturuldu: $DISK_IMG"
else
    log_warn "mkfs.ext4 bulunamadı (macOS). Alternatif yöntem kullanılacak."
    echo "QEMU boot sonrası rootfs'i manuel bağlaman gerekecek." >&2
    echo "Aşağıda NFS/9P paylaşım yöntemi açıklanacak." >&2
    # Boş imaj oluştur, QEMU içinde formatlanacak
    dd if=/dev/zero of="$DISK_IMG" bs=1M count=512 2>/dev/null
fi

echo
echo "=========================================="
echo "QEMU BAŞLATMA KOMUTU"
echo "=========================================="
echo
echo "Aşağıdaki komutu Mac terminalinde çalıştır:"
echo
echo "  $QEMU_BIN \\"
echo "    -M ${QEMU_MACHINE:-malta} \\"
echo "    -m ${QEMU_MEMORY:-256} \\"
echo "    -kernel '$DONOR_KERNEL_PATH' \\"
echo "    -drive file='$DISK_IMG',format=raw \\"
echo "    -append 'root=/dev/sda console=ttyS0' \\"
echo "    -nographic \\"
echo "    -net nic -net user,hostfwd=tcp::${QEMU_NET_HOST_PORT:-2222}-:${QEMU_NET_GUEST_PORT:-22} \\"
echo "    -fsdev local,id=humax_fs,path='$ROOTFS_DIR',security_model=none \\"
echo "    -device virtio-9p-pci,fsdev=humax_fs,mount_tag=humax_root"
echo
echo "=========================================="
echo "QEMU İÇİNDEN CHROOT ADIMLARI"
echo "=========================================="
echo
echo "QEMU açılınca OpenWrt shell'ine düşeceksin. Oradan:"
echo

SETUP_SCRIPT="$EXTRACT_DIR/chroot-setup.sh"
cat > "$SETUP_SCRIPT" << 'CHROOT_EOF'
#!/bin/sh
# ==========================================================================
# QEMU içinde çalıştırılacak chroot kurulum script'i
# ==========================================================================
# Bu script'i QEMU'daki OpenWrt shell'inde çalıştır.
# Humax rootfs'ini bağlar ve chroot ortamını hazırlar.
# ==========================================================================

HUMAX_ROOT="/mnt/humax"

echo "[1/5] Humax rootfs'i bağlanıyor..."
mkdir -p "$HUMAX_ROOT"

# Yöntem A: 9P (virtio-9p ile paylaşılmışsa)
if grep -q "9p" /proc/filesystems 2>/dev/null; then
    mount -t 9p -o trans=virtio humax_root "$HUMAX_ROOT" 2>/dev/null && {
        echo "  -> 9P ile bağlandı."
    } || {
        echo "  -> 9P başarısız, disk imajı deneniyor..."
        mount /dev/sda "$HUMAX_ROOT" 2>/dev/null || {
            echo "HATA: Humax rootfs bağlanamadı." >&2
            exit 1
        }
    }
else
    mount /dev/sda "$HUMAX_ROOT" 2>/dev/null || {
        echo "HATA: Humax rootfs bağlanamadı." >&2
        exit 1
    }
fi

echo "[2/5] Sanal dosya sistemleri bağlanıyor..."
mount -t proc proc "$HUMAX_ROOT/proc" 2>/dev/null || mkdir -p "$HUMAX_ROOT/proc"
mount -t sysfs sys "$HUMAX_ROOT/sys" 2>/dev/null || mkdir -p "$HUMAX_ROOT/sys"
mount -t devtmpfs dev "$HUMAX_ROOT/dev" 2>/dev/null || {
    mkdir -p "$HUMAX_ROOT/dev"
    # Temel device node'ları oluştur
    mknod "$HUMAX_ROOT/dev/null" c 1 3 2>/dev/null || true
    mknod "$HUMAX_ROOT/dev/zero" c 1 5 2>/dev/null || true
    mknod "$HUMAX_ROOT/dev/random" c 1 8 2>/dev/null || true
    mknod "$HUMAX_ROOT/dev/urandom" c 1 9 2>/dev/null || true
    mknod "$HUMAX_ROOT/dev/console" c 5 1 2>/dev/null || true
}

echo "[3/5] DNS çözümleme ayarlanıyor..."
if [ -f "$HUMAX_ROOT/etc/resolv.conf" ]; then
    cp "$HUMAX_ROOT/etc/resolv.conf" "$HUMAX_ROOT/etc/resolv.conf.bak"
fi
echo "nameserver 8.8.8.8" > "$HUMAX_ROOT/etc/resolv.conf"

echo "[4/5] Donanım hata tuzakları kuruluyor..."
# Donanıma bağlı servislerin çökmesini engellemek için sahte device'lar
for devnode in /dev/brcm0 /dev/dvb /dev/video0 /dev/fb0 /dev/hdmi; do
    devpath="$HUMAX_ROOT$devnode"
    mkdir -p "$(dirname "$devpath")"
    ln -sf /dev/null "$devpath" 2>/dev/null || true
done

echo "[5/5] Chroot başlatılıyor..."
echo
echo "============================================"
echo "  HUMAX IRHD-5000S — Firmware Rehosting"
echo "  root@humax# shell'ine düşüyorsun."
echo "============================================"
echo
echo "Faydalı komutlar:"
echo "  ls /etc/init.d/           # Başlatma betikleri"
echo "  find / -name '*aes*'      # AES kütüphaneleri"
echo "  find / -name '*.so'       # Paylaşımlı kütüphaneler"
echo "  strings /usr/bin/openssl  # OpenSSL sürüm bilgisi"
echo "  cat /etc/passwd           # Kullanıcı hesapları"
echo "  ls /usr/lib/              # Kriptografi kütüphaneleri"
echo "  find / -name '*cas*'      # CAS modülleri"
echo "  find / -name '*key*'      # Anahtar dosyaları"
echo "  find / -name '*encrypt*'  # Şifreleme binary'leri"
echo
echo "Çıkmak için: exit"
echo

chroot "$HUMAX_ROOT" /bin/sh -l 2>/dev/null || \
chroot "$HUMAX_ROOT" /bin/ash 2>/dev/null || \
chroot "$HUMAX_ROOT" /bin/busybox sh 2>/dev/null || {
    echo "HATA: Chroot başarısız. Shell bulunamadı." >&2
    echo "Mevcut shell'ler:" >&2
    ls -la "$HUMAX_ROOT/bin/"*sh* 2>/dev/null || echo "  (hiç yok)" >&2
    exit 1
}

# Chroot'tan çıkınca temizlik
echo
echo "Chroot'tan çıkıldı. Temizlik yapılıyor..."
umount "$HUMAX_ROOT/proc" 2>/dev/null || true
umount "$HUMAX_ROOT/sys" 2>/dev/null || true
umount "$HUMAX_ROOT/dev" 2>/dev/null || true
CHROOT_EOF
chmod +x "$SETUP_SCRIPT"

echo "  # Script'i QEMU'ya kopyala ve çalıştır:"
echo "  # (Mac terminalinden, başka bir pencerede)"
echo "  scp -P ${QEMU_NET_HOST_PORT:-2222} '$SETUP_SCRIPT' root@localhost:/tmp/"
echo "  ssh -p ${QEMU_NET_HOST_PORT:-2222} root@localhost 'sh /tmp/chroot-setup.sh'"
echo
echo "  # Veya QEMU konsolunda doğrudan yapıştır:"
echo "  mkdir -p /mnt/humax"
echo "  mount -t 9p -o trans=virtio humax_root /mnt/humax"
echo "  mount -t proc proc /mnt/humax/proc"
echo "  mount -t sysfs sys /mnt/humax/sys"
echo "  chroot /mnt/humax /bin/sh"
echo
echo "=========================================="
log_ok "Chroot kurulum script'i: $SETUP_SCRIPT"
log_ok "Sonraki adım: QEMU'yu başlat, chroot'a gir, sonra 04-analyze-crypto.sh çalıştır."
