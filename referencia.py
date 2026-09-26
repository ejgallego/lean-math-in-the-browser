"""Independent reference for the differential test of Tunnell.lean (run in the browser via lean-vir).

Counts the integer solutions by BRUTE FORCE over the whole box x, y, z in [-R, R] (no symmetry
tricks, no square roots: a different algorithm from Tunnell.rep), and cross-checks the resulting
criterion against OEIS A003273 (congruent numbers; for squarefree n, the terms are exactly the n
that satisfy Tunnell's criterion).

Run: python referencia.py [limite]   -> writes referencia.json
"""
import json
import math
import sys


def rep_bruta(a, b, c, n):
    """#{(x, y, z) in Z^3 : a x^2 + b y^2 + c z^2 = n}, by enumerating the full box."""
    R = math.isqrt(n)
    total = 0
    for x in range(-R, R + 1):
        ax = a * x * x
        if ax > n:
            continue
        for z in range(-R, R + 1):
            az = ax + c * z * z
            if az > n:
                continue
            for y in range(-R, R + 1):
                if az + b * y * y == n:
                    total += 1
    return total


def libre_de_cuadrados(n):
    return n > 0 and all(n % (p * p) for p in range(2, math.isqrt(n) + 1))


def tunnell(n):
    if n % 2:
        f, s = rep_bruta(2, 1, 32, n), rep_bruta(2, 1, 8, n)
    else:
        f, s = rep_bruta(4, 1, 32, n // 2), rep_bruta(4, 1, 8, n // 2)
    return {"n": n, "squarefree": libre_de_cuadrados(n), "first": f, "second": s, "criterion": 2 * f == s}


if __name__ == "__main__":
    limite = int(sys.argv[1]) if len(sys.argv) > 1 else 400
    filas = [tunnell(n) for n in range(1, limite + 1)]
    oeis = {int(l.split()[1]) for l in open("b003273.txt") if l.strip() and not l.startswith("#")}
    assert max(oeis) >= limite, "the b-file must cover the range"
    malos = [r["n"] for r in filas if r["squarefree"] and r["criterion"] != (r["n"] in oeis)]
    print(f"n = 1..{limite}: {sum(r['squarefree'] for r in filas)} squarefree; "
          f"criterion = OEIS A003273 on all of them: {not malos} {malos[:10]}")
    json.dump(filas, open("referencia.json", "w"), indent=0)
