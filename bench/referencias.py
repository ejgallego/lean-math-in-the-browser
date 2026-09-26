"""Independent Python references for the Lean workloads, each by a DIFFERENT algorithm from the
Lean one wherever there is one, so that agreement is evidence and not an echo:

  tunnell         (x, z) enumeration with math.isqrt           Lean: moving pointer in y
  collatzRecord   memoised stopping times                      Lean: direct iteration per n
  primeCount      bytearray sieve with slice assignment        Lean: element-by-element sieve
  mertens         linear sieve of the Moebius function          Lean: sieve by primes and prime squares
  partitions      coin-change dynamic programming               Lean: Euler's pentagonal recurrence
  fib             iterative addition                            Lean: fast doubling
  isPrime         Miller-Rabin with different bases + known     Lean: bases 2..41
                  Mersenne exponents
  lifePopulation  numpy roll on the torus, same soup generator  Lean: explicit neighbour sums

Usage: python bench/referencias.py <workload> <arg>   -> the value, printed like the Lean CLI
"""
import math
import sys


def tunnell(n):
    def rep(a, c, m):
        t = 0
        for x in range(math.isqrt(m // a) + 1):
            rx = m - a * x * x
            for z in range(math.isqrt(rx // c) + 1):
                r = rx - c * z * z
                y = math.isqrt(r)
                if y * y == r:
                    t += (1 if x == 0 else 2) * (1 if y == 0 else 2) * (1 if z == 0 else 2)
        return t
    f, s = (rep(2, 32, n), rep(2, 8, n)) if n % 2 else (rep(4, 32, n // 2), rep(4, 8, n // 2))
    return f"{f} {s} {'true' if 2 * f == s else 'false'}"


def collatzRecord(N):
    memo = {1: 0}

    def steps(n):
        camino = []
        while n not in memo:
            camino.append(n)
            n = n // 2 if n % 2 == 0 else 3 * n + 1
        s = memo[n]
        for m in reversed(camino):
            s += 1
            memo[m] = s
        return memo[camino[0]] if camino else memo[n]
    best, bs = 1, 0
    for n in range(1, N + 1):
        s = steps(n)
        if s > bs:
            best, bs = n, s
    return f"{best} {bs}"


def primeCount(N):
    if N < 2:
        return "0"
    a = bytearray([1]) * (N + 1)
    a[0] = a[1] = 0
    for p in range(2, math.isqrt(N) + 1):
        if a[p]:
            a[p * p::p] = bytearray(len(range(p * p, N + 1, p)))
    return str(sum(a))


def mertens(N):
    mu = [0] * (N + 1)
    mu[1] = 1
    primos, compuesto = [], bytearray(N + 1)
    for i in range(2, N + 1):
        if not compuesto[i]:
            primos.append(i)
            mu[i] = -1
        for p in primos:
            if i * p > N:
                break
            compuesto[i * p] = 1
            if i % p == 0:
                mu[i * p] = 0
                break
            mu[i * p] = -mu[i]
    return str(sum(mu))


def partitions(n):
    p = [1] + [0] * n
    for k in range(1, n + 1):
        for m in range(k, n + 1):
            p[m] += p[m - k]
    return str(p[n])


def fib(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return str(a)


MERSENNE = {2, 3, 5, 7, 13, 17, 19, 31, 61, 89, 107, 127, 521, 607, 1279}


def isPrime(n):
    if n + 1 == 1 << (n + 1).bit_length() - 1 and n > 2:          # n = 2^k - 1: the known list decides
        return "true" if (n + 1).bit_length() - 1 in MERSENNE else "false"
    if n < 2:
        return "false"
    for p in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71):
        if n % p == 0:
            return "true" if n == p else "false"
    d, s = n - 1, 0
    while d % 2 == 0:
        d //= 2
        s += 1
    for a in (43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 101, 103, 107, 109, 113):   # other bases than Lean's
        x = pow(a, d, n)
        if x in (1, n - 1):
            continue
        for _ in range(s - 1):
            x = x * x % n
            if x == n - 1:
                break
        else:
            return "false"
    return "true"


def lifePopulation(k):
    import numpy as np
    side, s, cells = 64, 20260926, []
    for _ in range(side * side):
        s = (1103515245 * s + 12345) % 2147483648
        cells.append(s % 10 < 3)
    g = np.array(cells, dtype=np.uint8).reshape(side, side)
    for _ in range(k):
        n = sum(np.roll(np.roll(g, dy, 0), dx, 1) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx)
        g = np.where(g == 1, np.isin(n, (2, 3, 7, 8)), np.isin(n, (3, 7))).astype(np.uint8)
    return str(int(g.sum()))


if __name__ == "__main__":
    sys.set_int_max_str_digits(0)
    print(globals()[sys.argv[1]](int(sys.argv[2])))
