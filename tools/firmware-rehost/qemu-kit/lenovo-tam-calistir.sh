#!/usr/bin/env bash
# ==========================================================================
# Humax NAND -> QEMU : Tam Otomatik (Lenovo/Linux)
# ==========================================================================
# TAM 132MB ham NAND dokumunu al, bastan sona isle ve QEMU'da calistir.
# Ogrendigimiz her sey burada: OOB temizleme + swap32 (byte-order) +
# kayma yamasi (+507904) + id-table/fragment tamiri + squashfs cikarma +
# QEMU MIPS big-endian boot.
#
# Kullanim:
#   ./lenovo-tam-calistir.sh /tam/yol/S34ML01G200BHI00@BGA63_2147.BIN
#
# Notlar:
# - Ham dokum OOB'lu (~132MB) VEYA OOB'suz (128MB) olabilir; script anlar.
# - Metadata bu dokumde hasarliysa, tam rootfs cikmayabilir; o durumda
#   kurtarilan parcalarla QEMU ortami yine acilir.
# ==========================================================================
set -euo pipefail

DUMP="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$SCRIPT_DIR/.work"
mkdir -p "$WORK"

if [[ -z "$DUMP" || ! -f "$DUMP" ]]; then
    echo "Kullanim: $0 /yol/S34ML01G200BHI00@BGA63_2147.BIN"
    exit 1
fi

echo "[1/6] Bagimliliklar (sudo)..."
sudo apt-get update -qq
sudo apt-get install -y -qq python3 qemu-system-mips squashfs-tools e2fsprogs wget

echo "[2/6] OOB temizle + byte-order (swap32) + squashfs cikar..."
python3 - "$DUMP" "$WORK" <<'PYEOF'
import sys, array, struct, os
dump, work = sys.argv[1], sys.argv[2]
raw = open(dump,'rb').read()
print("  ham boyut:", len(raw))
# OOB tespit (2048+64). Boyut 2112'nin kati ve 2048'e da bolunuyorsa OOB var.
page, oob, full = 2048, 64, 2112
has_oob = (len(raw) % full == 0)
if has_oob and len(raw)//full in (16384,32768,65536,131072):
    print("  OOB tespit edildi, temizleniyor...")
    clean = bytearray()
    for p in range(len(raw)//full):
        clean += raw[p*full:p*full+page]
    clean = bytes(clean)
else:
    print("  OOB yok / zaten temiz.")
    clean = raw
# swap32
n = len(clean) & ~3
a = array.array('I'); a.frombytes(clean[:n]); a.byteswap()
sw = a.tobytes() + clean[n:]
# squashfs magic bul (swap sonrasi 'hsqs')
pos = sw.find(b'hsqs')
if pos < 0:
    # swapsiz dene
    pos = clean.find(b'hsqs')
    sw = clean
if pos < 0:
    print("  HATA: SquashFS (hsqs) bulunamadi."); sys.exit(1)
print("  SquashFS @", hex(pos))
sqfs = bytearray(sw[pos:])
# Superblock oku
it = struct.unpack_from('<Q', sqfs, 64)[0]
print("  superblock inode_table_start:", it)
# --- Kayma tespiti: it civarindan ardisik metadata blok zinciri ara ---
import zlib
def chain_len(off):
    c=0; o=off
    while o+2 < len(sqfs):
        L=struct.unpack_from('<H',sqfs,o)[0]; real=L&0x7fff; comp=not(L&0x8000)
        if real==0 or real>8192: break
        try:
            (zlib.decompress(sqfs[o+2:o+2+real]) if comp else sqfs[o+2:o+2+real])
        except: break
        c+=1; o+=2+real
    return c,o
best=(0,it,it)
for cand in range(it, min(it+800000, len(sqfs)-2)):
    if sqfs[cand:cand+2] in (b'\x78\x01',b'\x78\x5e',b'\x78\x9c',b'\x78\xda'):
        cl,end=chain_len(cand)
        if cl>best[0]: best=(cl,cand,end)
        if cl>=12: break
shift = best[1]-it
print(f"  en uzun metadata zinciri @ {best[1]} ({best[0]} blok), KAYMA={shift}")
# --- Superblock yamala: tablo ofsetleri += shift ---
for off in (40,48,64,72,80):
    v=struct.unpack_from('<Q',sqfs,off)[0]
    struct.pack_into('<Q',sqfs,off,v+shift)
# fragment ve export etkisizlestir (hasarli olabilir)
struct.pack_into('<I',sqfs,16,0)          # fragments=0
struct.pack_into('<q',sqfs,80,-1)         # frag_table=-1
fl=struct.unpack_from('<H',sqfs,24)[0]; struct.pack_into('<H',sqfs,24,fl&~0x0080)
struct.pack_into('<q',sqfs,88,-1)         # lookup=-1
# id-table uydur
bu=struct.unpack_from('<Q',sqfs,40)[0]
if bu+14>len(sqfs): sqfs.extend(b'\x00'*(bu+14-len(sqfs)))
struct.pack_into('<H',sqfs,bu,0x8004); struct.pack_into('<I',sqfs,bu+2,0)
struct.pack_into('<Q',sqfs,bu+6,bu); struct.pack_into('<Q',sqfs,40,bu+14)
struct.pack_into('<Q',sqfs,48,bu+6); struct.pack_into('<H',sqfs,26,1)
open(os.path.join(work,'rootfs.sqfs'),'wb').write(sqfs)
print("  rootfs.sqfs yazildi (yamalanmis).")
PYEOF

echo "[3/6] unsquashfs ile rootfs cikariliyor..."
rm -rf "$WORK/rootfs"
if unsquashfs -d "$WORK/rootfs" "$WORK/rootfs.sqfs" 2>&1 | tail -5; then
    NF=$(find "$WORK/rootfs" -type f 2>/dev/null | wc -l)
    echo "  cikarilan dosya: $NF"
else
    echo "  [UYARI] Tam cikarma basarisiz (metadata hasari). Kurtarilan parcalar kullanilacak."
fi

echo "[4/6] Rootfs (veya kurtarilan parcalar) disk imajina yaziliyor..."
SRC="$WORK/rootfs"
[[ -d "$SRC" && $(find "$SRC" -type f 2>/dev/null | wc -l) -gt 5 ]] || SRC="$SCRIPT_DIR/humax-recovered"
IMG="$WORK/humax.ext2"
dd if=/dev/zero of="$IMG" bs=1M count=96 2>/dev/null
mke2fs -q -F -t ext2 -d "$SRC" "$IMG" 2>/dev/null || mke2fs -q -F -t ext2 "$IMG"
echo "  imaj: $IMG (kaynak: $SRC)"

echo "[5/6] MIPS big-endian donor kernel indiriliyor..."
KERNEL="$WORK/openwrt-malta-be.elf"
[[ -f "$KERNEL" ]] || wget -q -O "$KERNEL" \
  "https://downloads.openwrt.org/releases/23.05.5/targets/malta/be/openwrt-23.05.5-malta-be-vmlinux-initramfs.elf" \
  || { echo "  [UYARI] Kernel inemedi; elle indir: https://downloads.openwrt.org/releases/23.05.5/targets/malta/be/"; }

echo "[6/6] QEMU baslatiliyor..."
echo "  Boot bitince kabukta:  mount -t ext2 /dev/sda /mnt; ls /mnt"
echo "  Cikis: Ctrl-A sonra X"
sleep 2
exec qemu-system-mips -M malta -m 256 -kernel "$KERNEL" \
    -drive file="$IMG",format=raw,if=ide -nographic -append "console=ttyS0 rootwait"
