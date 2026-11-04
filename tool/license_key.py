"""Creates the licence key and codes using only the Python standard library.

  python tool/license_key.py new-key
      Writes the secret key to bokforing-hemlig-nyckel.txt in your home folder
      (outside this repository) and prints the public key for the app.

  python tool/license_key.py code ID NAME ORG UNTIL
      Prints a code signed with that secret key. UNTIL is YYYY-MM-DD, or empty
      for no end date.

The secret key file is never printed. Keep it out of the repository.
"""
import base64
import hashlib
import os
import secrets
import sys

P = 2 ** 255 - 19
Q = 2 ** 252 + 27742317777372353535851937790883648493
D = -121665 * pow(121666, P - 2, P) % P
SQRT_M1 = pow(2, (P - 1) // 4, P)


def _x_from_y(y, sign):
    u = (y * y - 1) * pow(D * y * y + 1, P - 2, P) % P
    x = pow(u, (P + 3) // 8, P)
    if (x * x - u) % P:
        x = x * SQRT_M1 % P
    return P - x if x % 2 != sign else x


_GY = 4 * pow(5, P - 2, P) % P
_GX = _x_from_y(_GY, 0)
G = (_GX, _GY, 1, _GX * _GY % P)


def _add(a, b):
    A = (a[1] - a[0]) * (b[1] - b[0]) % P
    B = (a[1] + a[0]) * (b[1] + b[0]) % P
    C = 2 * a[3] * b[3] * D % P
    E = 2 * a[2] * b[2] % P
    F, H, I, J = (B - A) % P, (E - C) % P, (E + C) % P, (B + A) % P
    return (F * H % P, I * J % P, H * I % P, F * J % P)


def _mul(n, pt):
    out = (0, 1, 1, 0)
    while n:
        if n & 1:
            out = _add(out, pt)
        pt = _add(pt, pt)
        n >>= 1
    return out


def _compress(pt):
    z = pow(pt[2], P - 2, P)
    x, y = pt[0] * z % P, pt[1] * z % P
    return (y | ((x & 1) << 255)).to_bytes(32, 'little')


def _sha(b):
    return int.from_bytes(hashlib.sha512(b).digest(), 'little')


def _expand(seed):
    h = hashlib.sha512(seed).digest()
    a = int.from_bytes(h[:32], 'little') & ((1 << 254) - 8) | (1 << 254)
    return a, h[32:]


def public_key(seed):
    return _compress(_mul(_expand(seed)[0], G))


def sign(seed, message):
    a, prefix = _expand(seed)
    pub = _compress(_mul(a, G))
    r = _sha(prefix + message) % Q
    big_r = _compress(_mul(r, G))
    s = (r + _sha(big_r + pub + message) * a) % Q
    return big_r + s.to_bytes(32, 'little')


def _b64(b):
    return base64.urlsafe_b64encode(b).rstrip(b'=').decode()


def _unb64(s):
    return base64.urlsafe_b64decode(s + '=' * (-len(s) % 4))


def make_code(seed, code_id, name, org, until):
    payload = '|'.join(part.replace('|', ' ') for part in (code_id, name, org, until)).encode('utf-8')
    return f'BOK1.{_b64(payload)}.{_b64(sign(seed, payload))}'


# The published test vector from RFC 8032, so a mistake above stops everything.
_VECTOR = bytes.fromhex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60')
assert public_key(_VECTOR).hex() == 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
assert sign(_VECTOR, b'').hex().startswith('e5564300c360ac72')

KEY_FILE = os.path.join(os.path.expanduser('~'), 'bokforing-hemlig-nyckel.txt')


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ''
    if command == 'new-key':
        if os.path.exists(KEY_FILE):
            sys.exit('A key already exists; a new one would make every code invalid.')
        seed = secrets.token_bytes(32)
        with open(KEY_FILE, 'w', encoding='ascii') as f:
            f.write(f'{_b64(seed)}.{_b64(public_key(seed))}\n')
        print(_b64(public_key(seed)))
    elif command == 'code':
        with open(KEY_FILE, encoding='ascii') as f:
            seed = _unb64(f.read().strip().split('.')[0])
        print(make_code(seed, *sys.argv[2:6]))
    elif command == 'vector-code':
        print(make_code(_VECTOR, *sys.argv[2:6]))
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
