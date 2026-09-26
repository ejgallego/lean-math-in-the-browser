"""Second independent reference: the counts by enumerating (x, z) and testing y with math.isqrt
(no moving pointer, no Lean). Faster than the brute force of referencia.py, so it reaches
n = 10,000 and random n in the millions.

Usage: python tests/referencia_rapida.py <from> <to>        -> lines "n first second criterion squarefree"
       python tests/referencia_rapida.py --ns n1 n2 ...
"""
import math
import sys


def rep(a, c, n):
    total = 0
    for x in range(math.isqrt(n // a) + 1):
        rx = n - a * x * x
        for z in range(math.isqrt(rx // c) + 1):
            r = rx - c * z * z
            y = math.isqrt(r)
            if y * y == r:
                total += (1 if x == 0 else 2) * (1 if y == 0 else 2) * (1 if z == 0 else 2)
    return total


def squarefree(n):
    return n > 0 and all(n % (p * p) for p in range(2, math.isqrt(n) + 1))


def linea(n):
    f, s = (rep(2, 32, n), rep(2, 8, n)) if n % 2 else (rep(4, 32, n // 2), rep(4, 8, n // 2))
    return f"{n} {f} {s} {'true' if 2 * f == s else 'false'} {'true' if squarefree(n) else 'false'}"


if __name__ == "__main__":
    a = sys.argv[1:]
    ns = [int(x) for x in a[1:]] if a[0] == "--ns" else range(int(a[0]), int(a[1]) + 1)
    print("\n".join(linea(n) for n in ns))
