#!/usr/bin/env python3
"""
SquashFS metadata blok decompress brute-force.

Superblock 4-byte-swap ile cozuluyor ama tablolar acilmiyor. Bu script
inode/dir/frag tablolarindaki metadata bloklarina farkli byte-order
donusumleri uygulayip GERCEKTEN zlib ile acmayi dener. Hangisi acilirsa
dogru sema odur.

Kullanim: python3 diag2-decompress.py <rootfs.sqfs>
"""
import sys, struct, array, zlib

if len(sys.argv) < 2:
    print("Kullanim: python3 diag2-decompress.py <rootfs.sqfs>")
    sys.exit(1)

data = open(sys.argv[1], "rb").read()

# Superblock'u 4-byte-swap ile coz, tablo ofsetlerini al
sbraw = bytearray(data[:96])
arr = array.array("I"); arr.frombytes(bytes(sbraw)); arr.byteswap()
sb = bytes(arr)
inode_table = struct.unpack("<Q", sb[64:72])[0]
dir_table = struct.unpack("<Q", sb[72:80])[0]
frag_table = struct.unpack("<Q", sb[80:88])[0]
id_table = struct.unpack("<Q", sb[48:56])[0]
print(f"inode_table={inode_table} dir_table={dir_table} frag_table={frag_table} id_table={id_table}")

def swap16(buf):
    b = bytearray(buf); n = len(b) & ~1
    a = array.array("H"); a.frombytes(bytes(b[:n])); a.byteswap()
    return bytes(a) + bytes(b[n:])

def swap32(buf):
    b = bytearray(buf); n = len(b) & ~3
    a = array.array("I"); a.frombytes(bytes(b[:n])); a.byteswap()
    return bytes(a) + bytes(b[n:])

transforms = {
    "ham (identity)": lambda x: x,
    "swap16 (2-byte)": swap16,
    "swap32 (4-byte)": swap32,
}

def try_zlib(payload):
    """Farkli zlib/deflate modlariyla acmayi dener."""
    for wbits, ad in [(15, "zlib"), (-15, "raw-deflate"), (31, "gzip")]:
        try:
            d = zlib.decompressobj(wbits)
            out = d.decompress(payload)
            if len(out) > 0:
                return f"{ad} OK -> {len(out)} byte cozuldu"
        except Exception:
            pass
    return None

def test_offset(isim, offset):
    print(f"\n=== {isim} @ {offset} (0x{offset:x}) ===")
    if offset < 0 or offset + 4 > len(data):
        print("  ofset gecersiz")
        return
    # Hizalanmis genis pencere al (transform icin), sonra alan ofsetine kaydir
    win_start = offset & ~3
    shift = offset - win_start
    window = data[win_start: win_start + 8192 + 8]
    for tname, tf in transforms.items():
        tw = tf(window)[shift:]
        if len(tw) < 4:
            continue
        # Metadata blok: 2-byte uzunluk (LE), bit15=uncompressed
        for endlbl, lenval in [("LE", struct.unpack("<H", tw[:2])[0]),
                               ("BE", struct.unpack(">H", tw[:2])[0])]:
            comp = not (lenval & 0x8000)
            reallen = lenval & 0x7fff
            if reallen == 0 or reallen > 8192:
                continue
            payload = tw[2:2+reallen]
            if len(payload) < reallen:
                continue
            if comp:
                res = try_zlib(payload)
                if res:
                    print(f"  >>> BULUNDU: transform={tname}, len_endian={endlbl}, "
                          f"len={reallen}, {res}")
                    return (tname, endlbl, reallen)
            else:
                print(f"  transform={tname} len_endian={endlbl}: sikistirilmamis blok len={reallen}")
    print("  (bu tabloda acilabilir blok bulunamadi)")
    return None

for isim, off in [("inode_table", inode_table), ("dir_table", dir_table),
                  ("frag_table", frag_table)]:
    test_offset(isim, off)

print("\n=== SONUC ===")
print("Yukarida 'BULUNDU' satiri varsa, o transform+endian ile tum imaji")
print("donusturup unsquashfs calistiracagiz. Hicbiri yoksa veri sikistirmasi")
print("gzip degil ya da ofsetler hatali demektir.")
