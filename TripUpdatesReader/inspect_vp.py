#!/usr/bin/env python3
"""
inspect_vp.py — Inspecciona vehiclePositions.pb de Tuvisa (Vitoria-Gasteiz)
Imprime la estructura completa del FeedMessage en formato jerárquico.
"""

import sys
import struct
import os

PB_FILE = os.path.join(os.path.dirname(__file__), "..", "vehiclePositions.pb")

data = open(PB_FILE, "rb").read()
print(f"Tamaño del fichero: {len(data)} bytes\n")

# ---------------------------------------------------------------------------
# Decodificador genérico de wire format protobuf
# ---------------------------------------------------------------------------

def read_varint(d, pos):
    result, shift = 0, 0
    while pos < len(d):
        b = d[pos]; pos += 1
        result |= (b & 0x7F) << shift
        if not (b & 0x80):
            return result, pos
        shift += 7
    return None, pos

def read_ld(d, pos):
    length, pos2 = read_varint(d, pos)
    if length is None or pos2 + length > len(d):
        return None, pos
    return d[pos2:pos2 + length], pos2 + length

def is_printable_utf8(b):
    try:
        text = b.decode('utf-8')
        return text, all(0x20 <= ord(c) < 0x7f or c in '\n\r\t' for c in text)
    except Exception:
        return None, False

def parse_message(d, indent=0, max_indent=6, label=""):
    pos = 0
    pfx = "  " * indent
    if label:
        print(f"{pfx}[{label}]")
    while pos < len(d):
        tag_val, pos2 = read_varint(d, pos)
        if tag_val is None:
            break
        field = tag_val >> 3
        wire  = tag_val & 7
        pos   = pos2

        if wire == 0:                          # varint
            v, pos = read_varint(d, pos)
            if v is None:
                break
            signed = v if v < (1 << 63) else v - (1 << 64)
            print(f"{pfx}  field={field}  varint={v}  (signed={signed})")

        elif wire == 2:                        # length-delimited
            sub, pos = read_ld(d, pos)
            if sub is None:
                print(f"{pfx}  field={field}  LD [TRUNCADO]")
                break
            text, printable = is_printable_utf8(sub)
            if printable:
                print(f"{pfx}  field={field}  string={repr(text)}")
            else:
                print(f"{pfx}  field={field}  bytes={len(sub)}")
                if indent < max_indent:
                    parse_message(sub, indent + 1, max_indent)

        elif wire == 1:                        # 64-bit fixed
            raw = d[pos:pos + 8]
            dbl = struct.unpack_from('<d', raw)[0]
            print(f"{pfx}  field={field}  64bit={raw.hex()}  (double={dbl:.6f})")
            pos += 8

        elif wire == 5:                        # 32-bit fixed
            raw = d[pos:pos + 4]
            flt = struct.unpack_from('<f', raw)[0]
            print(f"{pfx}  field={field}  32bit={raw.hex()}  (float={flt:.6f})")
            pos += 4

        else:
            print(f"{pfx}  field={field}  wire={wire}  [TIPO DESCONOCIDO — abortando]")
            break

# ---------------------------------------------------------------------------
# Parsear FeedMessage completo
# ---------------------------------------------------------------------------

def parse_feed_message(d, max_entities=None):
    pos = 0
    entity_count = 0

    while pos < len(d):
        tag_val, pos2 = read_varint(d, pos)
        if tag_val is None:
            break
        field = tag_val >> 3
        wire  = tag_val & 7
        pos   = pos2

        if wire == 2:
            sub, pos = read_ld(d, pos)
            if sub is None:
                print("  [TRUNCADO]")
                break
            if field == 1:
                print("=== FeedHeader ===")
                parse_message(sub, 1, 2, label="header")
                print()
            elif field == 2:
                entity_count += 1
                if max_entities is None or entity_count <= max_entities:
                    print(f"=== FeedEntity #{entity_count} ===")
                    parse_message(sub, 1, 6)
                    print()
                else:
                    # Solo contar el resto
                    pass
            else:
                text, printable = is_printable_utf8(sub)
                if printable:
                    print(f"  field={field}  string={repr(text)}")
                else:
                    print(f"  field={field}  bytes={len(sub)}")
        elif wire == 0:
            v, pos = read_varint(d, pos)
            print(f"  field={field}  varint={v}")
        else:
            # Saltar campo desconocido
            if wire == 1: pos += 8
            elif wire == 5: pos += 4
            else: break

    return entity_count

# ---------------------------------------------------------------------------
# Ejecución
# ---------------------------------------------------------------------------

MAX_ENTITIES = int(sys.argv[1]) if len(sys.argv) > 1 else 3

print("=" * 60)
print(f"Mostrando hasta {MAX_ENTITIES} entidades  (pasa un número como argumento para ver más)")
print("=" * 60)
print()

total = parse_feed_message(data, max_entities=MAX_ENTITIES)

print(f"\n{'=' * 60}")
print(f"TOTAL de FeedEntity en el fichero: {total}")
print("=" * 60)

