#!/usr/bin/env python3
"""Extrae trip_ids y stop_ids de las primeras N entidades de tripUpdates.pb"""
import sys, os

DATA_FILE = os.path.join(os.path.dirname(__file__), "..", "tripUpdates.pb")
data = open(DATA_FILE, "rb").read()

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

def parse_message(d, indent=0, max_indent=5, label=""):
    pos = 0
    pfx = "  " * indent
    if label: print(f"{pfx}[{label}]")
    while pos < len(d):
        tag_val, pos2 = read_varint(d, pos)
        if tag_val is None: break
        field = tag_val >> 3; wire = tag_val & 7; pos = pos2
        if wire == 0:
            v, pos = read_varint(d, pos)
            if v is None: break
            s = v if v < (1 << 63) else v - (1 << 64)
            print(f"{pfx}  field={field} varint={v} (signed={s})")
        elif wire == 2:
            sub, pos = read_ld(d, pos)
            if sub is None:
                print(f"{pfx}  field={field} LD [TRUNCADO]"); break
            try:
                text = sub.decode('utf-8')
                if all(0x20 <= ord(c) < 0x7f or c in '\n\r\t' for c in text):
                    print(f"{pfx}  field={field} string={repr(text)}")
                else:
                    raise ValueError()
            except Exception:
                print(f"{pfx}  field={field} bytes={len(sub)}")
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

MAX = int(sys.argv[1]) if len(sys.argv) > 1 else 3

pos = 0
_, pos = read_varint(data, pos)
_, pos = read_ld(data, pos)   # saltar FeedHeader

count = 0
while pos < len(data) and count < MAX:
    _, pos2 = read_varint(data, pos)
    entity, pos = read_ld(data, pos2)
    if entity is None: break
    count += 1
    print(f"\n=== TripUpdate Entity #{count} ===")
    parse_message(entity, 0, 5)

print(f"\nTotal mostradas: {count}")

