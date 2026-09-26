#!/usr/bin/env python3
"""
SquashFS byte-order teshis araci.

Bu Broadcom/Humax dokumunde superblock 4-byte kelime swap'li ama tablolarin
durumu belirsiz. Bu script superblock'u cozer, tablo ofsetlerini bulur ve
o bolgelerin baytlarini farkli transform'lar altinda gosterir; boylece
hangi byte-order semasinin dogru oldugunu belirleriz.

Kullanim: python3 diag-squashfs.py <rootfs.sqfs>
"""
import sys, struct, array

if len(sys.argv) < 2:
    print("Kullanim: python3 diag-squashfs.py <rootfs.sqfs>")
    sys.exit(1)

data = open(sys.argv[1], "rb").read()
print(f"Dosya: {sys.argv[1]}  boyut: {len(data):,}")
print(f"Ilk 4 byte (ham): {data[:4]!r}")

# Superblock'u 4-byte kelime swap ile coz
sb = bytearray(data[:96])
arr = array.array("I"); arr.frombytes(bytes(sb)); arr.byteswap()
sb = bytes(arr)

magic = sb[:4]
inodes = struct.unpack("<I", sb[4:8])[0]
block_size = struct.unpack("<I", sb[12:16])[0]
comp = struct.unpack("<H", sb[20:22])[0]
block_log = struct.unpack("<H", sb[22:24])[0]
s_major = struct.unpack("<H", sb[28:30])[0]
s_minor = struct.unpack("<H", sb[30:32])[0]
root_inode = struct.unpack("<Q", sb[32:40])[0]
bytes_used = struct.unpack("<Q", sb[40:48])[0]
id_table = struct.unpack("<Q", sb[48:56])[0]
xattr_table = struct.unpack("<Q", sb[56:64])[0]
inode_table = struct.unpack("<Q", sb[64:72])[0]
dir_table = struct.unpack("<Q", sb[72:80])[0]
frag_table = struct.unpack("<Q", sb[80:88])[0]
lookup_table = struct.unpack("<Q", sb[88:96])[0]

print("\n=== Superblock (4-byte-swap ile cozuldu) ===")
print(f"  magic:        {magic!r}")
print(f"  inodes:       {inodes}")
print(f"  block_size:   {block_size}")
print(f"  compression:  {comp}  (1=gzip)")
print(f"  block_log:    {block_log}")
print(f"  version:      {s_major}.{s_minor}")
print(f"  root_inode:   0x{root_inode:x}")
print(f"  bytes_used:   {bytes_used}")
print(f"  id_table:     {id_table}")
print(f"  inode_table:  {inode_table}")
print(f"  dir_table:    {dir_table}")
print(f"  frag_table:   {frag_table}")
print(f"  lookup_table: {lookup_table}")

def hexdump(buf, base=0):
    out = []
    for i in range(0, len(buf), 16):
        chunk = buf[i:i+16]
        hexs = " ".join(f"{b:02x}" for b in chunk)
        out.append(f"    {base+i:08x}: {hexs}")
    return "\n".join(out)

def swap4(buf):
    b = bytearray(buf)
    n = len(b) & ~3
    a = array.array("I"); a.frombytes(bytes(b[:n])); a.byteswap()
    return bytes(a) + bytes(b[n:])

# Squashfs metadata blok: ilk 2 byte = uzunluk (bit15=1 ise sikistirilmamis).
# Sikistirilmis gzip blok: 2-byte uzunluk sonrasi 0x78 (zlib magic) beklenir.
def yorumla(buf):
    if len(buf) < 4:
        return "cok kisa"
    length = struct.unpack("<H", buf[:2])[0]
    comp_flag = "SIKISTIRILMAMIS" if (length & 0x8000) else "sikistirilmis"
    real_len = length & 0x7fff
    nxt = buf[2:4]
    zlib = " <- zlib(0x78) magic!" if buf[2] == 0x78 else ""
    return f"len_field=0x{length:04x} ({comp_flag}, gercek_uzunluk={real_len}) sonraki={nxt.hex()}{zlib}"

print("\n=== id_table bolgesi teshisi (ofset {}) ===".format(id_table))
for isim, offset in [("id_table", id_table), ("inode_table", inode_table),
                     ("dir_table", dir_table), ("frag_table", frag_table)]:
    if offset >= len(data) or offset < 0:
        print(f"\n  [{isim}] ofset {offset} dosya disinda, atlaniyor")
        continue
    region = data[offset:offset+32]
    region_sw = swap4(data[offset & ~3: (offset & ~3) + 36])[offset & 3: (offset & 3) + 32]
    print(f"\n  [{isim}] ofset {offset} (0x{offset:x})")
    print(f"    --- HAM (orijinal) ---")
    print(hexdump(region, offset))
    print(f"    yorum: {yorumla(region)}")
    print(f"    --- 4-BYTE SWAP ---")
    print(hexdump(region_sw, offset))
    print(f"    yorum: {yorumla(region_sw)}")

print("\n=== SONUC ===")
print("Hangi versiyonda 'len_field' makul (< block_size) ve sonrasinda")
print("0x78 (zlib) geliyorsa, tablo o byte-order'da dogru demektir.")
