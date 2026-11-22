#!/bin/sh
# eww-socket.sh - путь IPC-сокета, который Eww построит для этого конфига.
#
# usage: lib/eww-socket.sh <каталог конфига>
#
# Почему нужен свой расчёт: сокет Eww - это
#   $XDG_RUNTIME_DIR/eww-server_<хэш канонического пути конфига>
# (build/eww-src/crates/eww/src/paths.rs, DefaultHasher от PathBuf). Демон,
# запущенный при ДРУГОМ XDG_RUNTIME_DIR, слушает другой сокет: он жив, держит
# своё окно острова, но `reload`/`close` до него не доходят - снаружи это
# «тема применилась, а остров завис». Поэтому run-island.sh сверяет сокет
# каждого найденного демона с этим.
#
# Хэш Rust DefaultHasher (SipHash-1-3, ключи 0,0) повторён на python3: другого
# способа спросить Eww «какой у тебя сокет» нет - он печатает его только в лог
# при старте. Формула проверена сверкой с живым демоном (см. scripts/selftest.sh).
#
# Зависимости только из системы: sh, python3.
set -eu

[ $# -ge 1 ] || { echo "usage: eww-socket.sh <каталог конфига>" >&2; exit 2; }
CONF=$1
[ -d "$CONF" ] || { echo "нет каталога конфига: $CONF" >&2; exit 2; }

python3 - "$CONF" <<'PY'
import os, sys

MASK = (1 << 64) - 1

def _rotl(x, b):
    return ((x << b) | (x >> (64 - b))) & MASK

def _sipround(v):
    v0, v1, v2, v3 = v
    v0 = (v0 + v1) & MASK; v1 = _rotl(v1, 13); v1 ^= v0; v0 = _rotl(v0, 32)
    v2 = (v2 + v3) & MASK; v3 = _rotl(v3, 16); v3 ^= v2
    v0 = (v0 + v3) & MASK; v3 = _rotl(v3, 21); v3 ^= v0
    v2 = (v2 + v1) & MASK; v1 = _rotl(v1, 17); v1 ^= v2; v2 = _rotl(v2, 32)
    return [v0, v1, v2, v3]

def siphash13(k0, k1, data):
    v = [k0 ^ 0x736f6d6570736575, k1 ^ 0x646f72616e646f6d,
         k0 ^ 0x6c7967656e657261, k1 ^ 0x7465646279746573]
    n = len(data)
    i = 0
    while i + 8 <= n:
        m = int.from_bytes(data[i:i + 8], 'little')
        v[3] ^= m
        v = _sipround(v)
        v[0] ^= m
        i += 8
    tail = data[i:]
    b = (n & 0xff) << 56
    for j, byte in enumerate(tail):
        b |= byte << (8 * j)
    v[3] ^= b
    v = _sipround(v)
    v[0] ^= b
    v[2] ^= 0xff
    for _ in range(3):
        v = _sipround(v)
    return v[0] ^ v[1] ^ v[2] ^ v[3]

def default_hasher64(data):
    # std::collections::hash_map::DefaultHasher = SipHasher13 с ключами (0, 0).
    return siphash13(0, 0, data)

conf = os.path.realpath(sys.argv[1])
# Hash для Path пишет в hasher байты пути и завершающий 0xff (так str/Path
# отделяют «abc» от «abcd»). Сверено с живым демоном: путь
# /home/ig_ro/eww-island/eww -> eww-server_5e929ad971167bef.
raw = os.fsencode(conf) + b'\xff'
h = default_hasher64(raw)

runtime = os.environ.get('XDG_RUNTIME_DIR') or '/tmp'
print(os.path.join(runtime, 'eww-server_%x' % h))
PY
