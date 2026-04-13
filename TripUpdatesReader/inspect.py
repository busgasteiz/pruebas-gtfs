import sys

data = open("/Users/widemos/Downloads/tripUpdates.pb", "rb").read()

def read_varint(d, pos):
    result, shift = 0, 0
    while pos < len(d):
        b = d[pos]; pos += 1
        result |= (b & 0x7F) << shift
        if not (b & 0x80): return result, pos
        shift += 7
    return None, pos

def read_ld(d, pos):
    length, pos2 = read_varint(d, pos)
    if length is None or pos2 + length > len(d): return None, pos
    return d[pos2:pos2+length], pos2+length

def parse_message(d, indent=0, max_indent=4, label=""):
    pos = 0
    pfx = "  " * indent
    if label: print(f"{pfx}[{label}]")
    while pos < len(d):
        tag_val, pos2 = read_varint(d, pos)
        if tag_val is None: break
        field = tag_val >> 3
        wire = tag_val & 7
        pos = pos2
        if wire == 0:
            v, pos = read_varint(d, pos)
            if v is None: break
            # Show as signed int64
            s = v if v < (1 << 63) else v - (1 << 64)
            print(f"{pfx}  field={field} varint={v} (signed={s})")
        elif wire == 2:
            sub, pos = read_ld(d, pos)
            if sub is None:
                print(f"{pfx}  field={field} LD [TRUNCATED]"); break
            try:
                text = sub.decode('utf-8')
                if all(0x20 <= ord(c) < 0x7f or c in '\n\r\t' for c in text):
                    print(f"{pfx}  field={field} LD string={repr(text)}")
                else:
                    raise ValueError()
            except Exception:
                print(f"{pfx}  field={field} LD bytes={len(sub)}")
                if indent < max_indent:
                    parse_message(sub, indent + 1, max_indent)
        elif wire == 1:
            print(f"{pfx}  field={field} 64bit={d[pos:pos+8].hex()}")
            pos += 8
        elif wire == 5:
            print(f"{pfx}  field={field} 32bit={d[pos:pos+4].hex()}")
            pos += 4
        else:
            print(f"{pfx}  field={field} wire={wire} [UNKNOWN]"); break

# ---------- Parsear FeedMessage ----------
fm_pos = 0
_, fm_pos = read_varint(data, fm_pos)        # tag header
_, fm_pos = read_ld(data, fm_pos)            # skip header bytes

# Leer primera FeedEntity
_, fm_pos = read_varint(data, fm_pos)
entity1, fm_pos = read_ld(data, fm_pos)

# Leer segunda FeedEntity
_, fm_pos = read_varint(data, fm_pos)
entity2, fm_pos = read_ld(data, fm_pos)

print("=== Primera FeedEntity (completa) ===")
parse_message(entity1, 0, 5)

print("\n=== Segunda FeedEntity (completa) ===")
parse_message(entity2, 0, 5)
