| workload | size | native (ms) | WebAssembly (ms) | JavaScript (ms) | WASM ÷ native | WASM ÷ JS |
|---|--:|--:|--:|--:|--:|--:|
| Tunnell counts | 1,003 | 0.009 | 1.0 | 0.025 | 116 | 41 |
| Tunnell counts | 10,003 | 0.071 | 8.5 | 0.137 | 119 | 62 |
| Tunnell counts | 100,003 | 0.679 | 77.5 | 0.240 | 114 | 323 |
| Tunnell counts | 1,000,003 | 6.3 | 817.4 | 2.6 | 129 | 320 |
| Collatz record | 1,000 | 0.161 | 33.8 | 0.117 | 210 | 288 |
| Collatz record | 10,000 | 2.5 | 443.7 | 1.3 | 176 | 349 |
| Collatz record | 100,000 | 33.1 | 5,680.2 | 19.8 | 171 | 287 |
| prime sieve π(N) | 1,000 | 0.008 | 1.1 | 0.042 | 148 | 28 |
| prime sieve π(N) | 10,000 | 0.065 | 10.5 | 0.238 | 161 | 44 |
| prime sieve π(N) | 100,000 | 0.692 | 111.7 | 0.205 | 161 | 544 |
| prime sieve π(N) | 1,000,000 | 7.5 | 1,090.8 | 2.6 | 145 | 416 |
| Mertens M(N) | 1,000 | 0.018 | 2.6 | 0.093 | 144 | 28 |
| Mertens M(N) | 10,000 | 0.211 | 28.7 | 0.084 | 136 | 341 |
| Mertens M(N) | 100,000 | 1.9 | 309.0 | 3.0 | 162 | 104 |
| Mertens M(N) | 1,000,000 | 20.4 | 3,458.6 | 38.8 | 170 | 89 |
| Life B37/S2378 (generations) | 10 | 2.4 | 315.4 | 1.2 | 132 | 259 |
| Life B37/S2378 (generations) | 30 | 7.1 | 1,015.3 | 2.1 | 144 | 490 |
| Life B37/S2378 (generations) | 100 | 23.3 | 3,194.8 | 6.7 | 137 | 479 |
| partitions p(n), not printed | 100 | 0.005 | 0.805 | 0.011 | 153 | 73 |
| partitions p(n), not printed | 300 | 0.025 | 4.4 | 0.055 | 176 | 80 |
| partitions p(n), not printed | 1,000 | 2.5 | 27.2 | 0.411 | 11 | 66 |
| partitions p(n), not printed | 3,000 | 15.9 | 140.2 | 2.3 | 8.8 | 60 |
| partitions p(n), printed | 100 | 0.005 | 0.866 | 0.045 | 161 | 19 |
| partitions p(n), printed | 300 | 0.025 | 5.0 | 0.164 | 196 | 30 |
| partitions p(n), printed | 1,000 | 2.4 | 29.3 | 0.462 | 12 | 63 |
| partitions p(n), printed | 3,000 | 15.8 | 142.2 | 2.2 | 9.0 | 64 |
| Fibonacci F(n), not printed | 1,000 | 0.004 | 0.018 | 0.002 | 4.9 | 7.7 |
| Fibonacci F(n), not printed | 10,000 | 0.011 | 0.085 | 0.014 | 7.9 | 5.9 |
| Fibonacci F(n), not printed | 100,000 | 0.141 | 6.8 | 0.360 | 48 | 19 |
| Fibonacci F(n), not printed | 1,000,000 | 3.0 | 696.7 | 6.5 | 232 | 107 |
| Fibonacci F(n), printed | 1,000 | 0.102 | 0.048 | 0.004 | 0.5 | 14 |
| Fibonacci F(n), printed | 10,000 | 1.7 | 1.4 | 0.042 | 0.8 | 34 |
| Fibonacci F(n), printed | 100,000 | 92.4 | 140.7 | 1.2 | 1.5 | 115 |
| Fibonacci F(n), printed | 1,000,000 | 9,294.6 | 14,548.4 | 27.5 | 1.6 | 530 |
| Miller–Rabin (bits) | 31 | 0.003 | 0.444 | 0.016 | 154 | 27 |
| Miller–Rabin (bits) | 61 | 0.417 | 1.0 | 0.075 | 2.5 | 14 |
| Miller–Rabin (bits) | 89 | 0.461 | 1.7 | 0.326 | 3.6 | 5.1 |
| Miller–Rabin (bits) | 127 | 0.658 | 2.5 | 0.433 | 3.8 | 5.8 |
| Miller–Rabin (bits) | 521 | 5.6 | 34.0 | 6.7 | 6.1 | 5.1 |
| Miller–Rabin (bits) | 1,279 | 27.8 | 277.3 | 48.5 | 10.0 | 5.7 |
