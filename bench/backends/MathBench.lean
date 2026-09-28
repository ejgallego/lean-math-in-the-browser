module

public import Bench

@[expose] public section

-- Same textual results as Main.workload. This facade includes decimal formatting.
-- The *Bits entries format only log2, preserving the arithmetic-only distinction.
@[export fir_math_eval]
def mathEval (workload : UInt32) (n : Nat) : String :=
  match workload.toNat with
  | 0 => let v := Bench.tunnell n; s!"{v.first} {v.second} {v.criterion}"
  | 1 => let (a, b) := Bench.collatzRecord n; s!"{a} {b}"
  | 2 => toString (Bench.primeCount n)
  | 3 => toString (Bench.mertens n)
  | 4 => toString (Bench.partitions n)
  | 5 => toString (Bench.fib n)
  | 6 => toString (Bench.fibBits n)
  | 7 => toString (Bench.partitionsBits n)
  | 8 => toString (Bench.isPrime n)
  | 9 => toString (Bench.lifePopulation n)
  | _ => "invalid workload"
