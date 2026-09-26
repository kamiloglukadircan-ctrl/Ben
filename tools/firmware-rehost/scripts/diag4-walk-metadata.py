#!/usr/bin/env python3
"""
SquashFS metadata tablosu yuruyucu — hasarin nerede basladigini bulur.

inode_table_start'tan itibaren metadata bloklarini (2-byte uzunluk + zlib)
sirayla acar. Her blogun ofsetini, uzunlugunu ve acilip acilmadigini
raporlar. Ilk basarisiz blok, hasarin baslangicidir. Bu ofset bir NAND
sayfa sinirina (2048/2112 kati) denk geliyorsa, hasar bir sayfa kaymasidir
ve duzeltilebilir.

Girdi: swap32 ile duzeltilmis LE squashfs (rootfs_final.sqfs)
Kullanim: python3 diag4-walk-metadata.py <rootfs_final.sqfs>
"""
import sys, struct, zlib

if len(sys.argv) < 2:
    print("Kullanim: python3 diag4-walk-metadata.py <rootfs_final.sqfs>")
    sys.exit(1)

data = open(sys.argv[1], "rb").read()
inode_table = struct.unpack_from("<Q", data, 0x40)[0]
dir_table = struct.unpack_from("<Q", data, 0x48)[0]
print(f"inode_table_start={inode_table} (0x{inode_table:x})")
print(f"dir_table_start={dir_table} (0x{dir_table:x})")
print(f"inode tablosu boyutu ~ {dir_table - inode_table} byte\n")

def walk(name, start, end):
    print(f"=== {name}: {start} -> {end} ===")
    off = start
    idx = 0
    ok = 0
    while off < end - 2:
        length = struct.unpack_from("<H", data, off)[0]
        comp = not (length & 0x8000)
        real = length & 0x7fff
        if real == 0 or real > 8192:
            print(f"  blok#{idx} @ {off} (0x{off:x}): GECERSIZ uzunluk 0x{length:04x} -- HASAR BURADA")
            # Sayfa sinirina yakinlik kontrolu
            for page in (2048, 2112, 4096, 4224, 128*1024):
                m = off % page
                if m < 16 or m > page - 16:
                    print(f"     -> ofset {page}-bayt sayfa sinirina yakin (mod={m})")
            return off
        payload = data[off+2: off+2+real]
        if comp:
            try:
                out = zlib.decompress(payload)
                ok += 1
            except Exception as e:
                print(f"  blok#{idx} @ {off} (0x{off:x}): len={real} ACILAMADI ({e}) -- HASAR BURADA")
                for page in (2048, 2112, 4096, 4224, 128*1024):
                    m = off % page
                    if m < 16 or m > page - 16:
                        print(f"     -> ofset {page}-bayt sayfa sinirina yakin (mod={m})")
                return off
        else:
            out = payload
            ok += 1
        if idx < 3 or idx % 20 == 0:
            print(f"  blok#{idx} @ {off} (0x{off:x}): len={real} {'comp' if comp else 'raw'} -> {len(out)}b OK")
        off += 2 + real
        idx += 1
    print(f"  TAMAMI OK: {ok} blok acildi, {off}'e kadar")
    return None

fail = walk("inode_table", inode_table, dir_table)
print()
if fail is not None:
    print(f"SONUC: inode tablosu {fail} (0x{fail:x}) ofsetinde bozuluyor.")
    print(f"  inode_table_start'tan uzaklik: {fail - inode_table} byte")
    print(f"  Eger bu bir sayfa sinirina denk geliyorsa, sayfa kaymasi olabilir.")
else:
    print("SONUC: inode tablosu tamamen okundu — hasar dir/fragment tarafinda.")
