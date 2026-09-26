#!/usr/bin/env python3
"""
SquashFS id-tablosu tamiri.

Dokumun son sayfasindaki lokal bozulma yuzunden id (uid/gid) index
tablosu okunamiyor; superblock, veri bloklari ve diger tablolar saglam
(swap32 ile 310 gecerli zlib akisi dogrulandi). Bu script gecerli,
tek-girisli (id=0/root) bir id tablosu uydurur, superblock'un
id_table_start ve bytes_used alanlarini ona yonlendirir. Dosya
icerikleri/yapisi degismez — sadece 'unable to read id index table'
takilmasi kalkar.

Girdi:  swap32 ile duzeltilmis LE squashfs (rootfs_final.sqfs)
Cikti:  rootfs_fixed.sqfs

Kullanim: python3 09-fix-idtable.py <rootfs_final.sqfs> [cikti.sqfs]
"""
import sys, struct

if len(sys.argv) < 2:
    print("Kullanim: python3 09-fix-idtable.py <rootfs_final.sqfs> [cikti.sqfs]")
    sys.exit(1)

src = sys.argv[1]
dst = sys.argv[2] if len(sys.argv) > 2 else "rootfs_fixed.sqfs"

data = bytearray(open(src, "rb").read())

magic = bytes(data[:4])
if magic != b"hsqs":
    print(f"UYARI: magic {magic!r} beklenen b'hsqs' degil. Once swap32 uygulanmali.")

bytes_used = struct.unpack_from("<Q", data, 0x28)[0]
id_table_start = struct.unpack_from("<Q", data, 0x30)[0]
no_ids = struct.unpack_from("<H", data, 0x1a)[0]
print(f"Mevcut: bytes_used={bytes_used}  id_table_start={id_table_start}  no_ids={no_ids}")

# Sahte id tablosunu dosyanin (filesystem) sonuna yerlestir.
# Metadata blok: 2-byte header (0x8004 = sikistirilmamis, 4 byte veri) + id=0
MB = bytes_used
if MB + 14 > len(data):
    # Dosya yetersizse uzat
    data.extend(b"\x00" * (MB + 14 - len(data)))

struct.pack_into("<H", data, MB, 0x8004)     # metadata header: uncompressed, len=4
struct.pack_into("<I", data, MB + 2, 0)      # tek id degeri = 0 (root)
IDX = MB + 6
struct.pack_into("<Q", data, IDX, MB)        # index girisi -> metadata blok
new_bytes_used = IDX + 8

# Superblock'u yamala
struct.pack_into("<Q", data, 0x28, new_bytes_used)  # bytes_used
struct.pack_into("<Q", data, 0x30, IDX)             # id_table_start
struct.pack_into("<H", data, 0x1a, 1)               # no_ids = 1

open(dst, "wb").write(data)
print(f"Yamalandi -> {dst}")
print(f"  yeni id_table_start={IDX}  yeni bytes_used={new_bytes_used}")
print(f"\nSimdi calistir:")
print(f"  unsquashfs -d rootfs_out {dst}")
