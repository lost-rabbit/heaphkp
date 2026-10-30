"""Exact Python port of LSB utils.cpp packBitsBE / packBitsLE / EncodeStringLinkshell, to learn the real bit order."""

def pack_be(t, value, byte_off, bit_off, n):
    byte_off += bit_off >> 3
    bit_off %= 8
    mask = (0xFFFFFFFFFFFFFFFF >> (64 - n)) << bit_off
    value = (value << bit_off) & mask
    mask ^= 0xFFFFFFFFFFFFFFFF
    actual = (bit_off + n + 7) // 8
    data = int.from_bytes(bytes(t[byte_off:byte_off + actual]).ljust(8, b'\0'), 'little')
    data = (data & mask) | value
    db = data.to_bytes(9, 'little')[:actual] if data < (1 << 72) else None
    for i in range(actual): t[byte_off + i] = db[i]

def pack_le(t, value, bit_off, n, byte_off=0):
    byte_off += bit_off >> 3
    bit_off %= 8
    need = 1 if bit_off + n <= 8 else 2 if bit_off + n <= 16 else 4 if bit_off + n <= 32 else 8
    actual = (bit_off + n + 7) // 8
    mod = [0] * need
    for c in range(actual): mod[need - 1 - c] = t[byte_off + c]
    nbo = need * 8 - (bit_off + n)
    pack_be(mod, value, 0, nbo, n)
    for c in range(actual): t[byte_off + c] = mod[need - 1 - c]

def encode(sig):
    t = [0] * 32
    chars = 0
    for i, ch in enumerate(sig[:20]):
        if ch.isdigit(): v = ord(ch) - 48 + 53
        elif 'A' <= ch <= 'Z': v = ord(ch) - 65 + 27
        elif 'a' <= ch <= 'z': v = ord(ch) - 97 + 1
        else: v = 0
        pack_le(t, v, 6 * i, 6)
        chars += 1
    left = 8 - (chars * 6) % 8
    left = 6 if left in (8, 2) else left
    pack_le(t, 0xFF, 6 * chars, left)
    return bytes(t[:15])

def decode_msb(b):   # what heaphkp.lua does
    out = []
    for i in range(20):
        v = 0
        for k in range(6):
            pos = i * 6 + k
            byte = b[pos // 8] if pos // 8 < len(b) else 0
            v = v * 2 + ((byte >> (7 - pos % 8)) & 1)
        if v in (0, 63): break
        out.append(chr(96 + v) if v <= 26 else chr(64 + v - 26) if v <= 52 else chr(48 + v - 53))
    return ''.join(out)

if __name__ == '__main__':
    for name in ['Harem94761', 'Heaphsharem', 'A', 'Ab', 'Abc', 'Abcd', 'HeaphsHaremLinkshel1']:
        enc = encode(name)
        print(name, enc.hex(), '->', decode_msb(enc))
