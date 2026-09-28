import Fir.Wasm.Emit.ResidentBigNumeric
import Fir.Wasm.Emit.ResidentReferenceCount
import Fir.Wasm.Emit.ResidentRelease

namespace Fir.Wasm.Emit.ResidentNatMultiplication
open Lean Fir.Wasm Fir.Wasm.Concrete

/-! Schoolbook multiplication in base 2^32 over the existing little-endian
64-bit limb payload. Inputs are borrowed. Each inner accumulation is bounded by
(B-1)^2 + (B-1) + (B-1) = B^2-1, so unsigned i64 arithmetic loses no carry.

The layout requires exact allocation extents, not spare limb capacity. Build
in an upper-bound extent, then copy only if the top 64-bit limb is zero; retire
the construction buffer through the normal release/recycler path. One-limb
results go through makeNatural, preserving promoted and immediate conventions.
No unfinished buffer is passed to a natural-number consumer or exposed. -/

private def v (s : String) : FVarId := ⟨Name.str `mul s⟩
private def a := v "a"
private def b := v "b"
private def na := v "na"
private def nb := v "nb"
private def count := v "count"
private def capacity := v "capacity"
private def raw := v "raw"
private def out := v "out"
private def dead := v "dead"
private def i := v "i"
private def j := v "j"
private def k := v "k"
private def x := v "x"
private def y := v "y"
private def carry := v "carry"
private def sum := v "sum"
private def cell := v "cell"
private def zeroLoop := v "zero"
private def outerLoop := v "outer"
private def innerLoop := v "inner"
private def copyLoop := v "copy"
private def doneZero := v "doneZero"
private def doneMul := v "doneMul"
private def doneCopy := v "doneCopy"

private def set32 (local_ : FVarId) (n : UInt32) : List Instruction :=
  [.i32Const .uint32 n, .localSet local_]

private def advance (local_ : FVarId) : List Instruction :=
  [.localGet local_, .i32Const .uint32 1, .i32Add, .localSet local_]

private def address (ptr index : FVarId) (shift : UInt32) : List Instruction := [
  .localGet ptr, .i32Const .uint32 (UInt32.ofNat headerBytes), .i32Add,
  .localGet index, .i32Const .uint32 shift, .i32Shl, .i32Add]

private def asObject : List Instruction :=
  [.i64ExtendI32U .uint64, .i32WrapI64 .tobject]

private def allocate (n dest : FVarId) : List Instruction := [
  .i32Const .uint32 ObjectKind.natural.code,
  .i32Const .uint32 bigNaturalMarker, .i32Const .uint32 0,
  .localGet n, .call (.declaration ResidentBigNumeric.allocateName), .localSet dest]

private def releaseBuffer : List Instruction :=
  [.localGet raw] ++ asObject ++ [.localSet dead] ++
    ResidentRelease.checkedDecrementLocal dead

/-- Index is below twice the validated operand's 64-bit limb count. -/
private def digit (ptr index dest : FVarId) : List Instruction := [
  .localGet ptr, .i32Const .uint32 1, .i32And,
  .ifElse
    [.localGet index, .i32Eqz,
      .ifElse
        [.localGet ptr, .i32Const .uint32 1, .i32ShrU, .localSet dest]
        (set32 dest 0)]
    (address ptr index 2 ++ [.i32Load .uint32 0, .localSet dest])]

private def initializePayload : List Instruction := set32 i 0 ++ [
  .block doneZero [
    .loop zeroLoop ([
      .localGet i, .localGet capacity, .i32Eq, .ifElse [.br doneZero] []] ++
      address raw i 3 ++ [.i64Const .uint64 0, .i64Store .uint64 0] ++
      advance i ++ [.br zeroLoop])]]

private def inner : List Instruction := [
  .localGet i, .localGet j, .i32Add, .localSet k,
  .localGet j, .localGet nb, .i32Eq,
  .ifElse
    (address raw k 2 ++ [
      .localGet carry, .i32WrapI64 .uint32, .i32Store .uint32 0] ++
      advance i ++ [.br outerLoop]) []] ++
  digit b j y ++ address raw k 2 ++ [.localSet cell,
    .localGet x, .i64ExtendI32U .uint64,
    .localGet y, .i64ExtendI32U .uint64, .i64Mul,
    .localGet cell, .i32Load .uint32 0, .i64ExtendI32U .uint64, .i64Add,
    .localGet carry, .i64Add, .localSet sum,
    .localGet cell, .localGet sum, .i32WrapI64 .uint32, .i32Store .uint32 0,
    .localGet sum, .i64Const .uint64 32, .i64ShrU, .localSet carry] ++
  advance j ++ [.br innerLoop]

private def multiply : List Instruction := set32 i 0 ++ [
  .block doneMul [
    .loop outerLoop ([
      .localGet i, .localGet na, .i32Eq, .ifElse [.br doneMul] []] ++
      digit a i x ++ set32 j 0 ++ [
      .i64Const .uint64 0, .localSet carry,
      .loop innerLoop inner])]]

private def copyResult : List Instruction := allocate count out ++ set32 i 0 ++ [
  .block doneCopy [
    .loop copyLoop ([
      .localGet i, .localGet count, .i32Eq, .ifElse [.br doneCopy] []] ++
      address out i 3 ++ address raw i 3 ++ [
        .i64Load .uint64 0, .i64Store .uint64 0] ++
      advance i ++ [.br copyLoop])]] ++
  releaseBuffer ++ [.localGet out] ++ asObject ++ [.ret]

private def finish : List Instruction := [
  .localGet capacity, .localSet count,
  .localGet count, .i32Const .uint32 1, .i32Sub, .localSet k] ++
  address raw k 3 ++ [.i64Load .uint64 0, .i64Eqz,
    .ifElse [.localGet k, .localSet count] [],
    -- Nonzero operands imply at most one leading zero 64-bit limb.
    .localGet count, .i32Const .uint32 1, .i32Eq,
    .ifElse ([
      .localGet raw, .i32Load .uint32 (UInt32.ofNat headerBytes),
      .localGet raw, .i32Load .uint32 (UInt32.ofNat (headerBytes + 4)),
      .call (.declaration ResidentNumeric.makeNaturalName), .localSet out] ++
      releaseBuffer ++ [.localGet out] ++ asObject ++ [.ret]) [],
    .localGet count, .localGet capacity, .i32Eq,
    .ifElse ([.localGet raw] ++ asObject ++ [.ret]) copyResult]

private def returnOtherIfOne (unit other : FVarId) : List Instruction := [
  .localGet unit, .i32Const .tobject 3, .i32Eq,
  .ifElse [
    .localGet other, .call (.declaration ResidentReferenceCount.incrementOnceName),
    .localGet other, .ret] []]

/-- Same generic helper signature and borrowed-input contract as the bit walker. -/
def function (name : Name) : Function := {
  name
  params := #[(a, .tobject), (b, .tobject)]
  results := #[.tobject]
  locals := #[(na, .uint32), (nb, .uint32), (count, .uint32),
    (capacity, .uint32), (raw, .uint32), (out, .uint32), (dead, .tobject),
    (i, .uint32), (j, .uint32), (k, .uint32), (x, .uint32), (y, .uint32),
    (carry, .uint64), (sum, .uint64), (cell, .uint32)]
  body := [
    .localGet a, .call (.declaration ResidentBigNumeric.validateNaturalName),
    .localGet b, .call (.declaration ResidentBigNumeric.validateNaturalName),
    .localGet a, .i32Const .tobject 1, .i32Eq,
    .localGet b, .i32Const .tobject 1, .i32Eq, .i32Or,
    .ifElse [.i32Const .tobject 1, .ret] []] ++
    returnOtherIfOne a b ++ returnOtherIfOne b a ++ [
    .localGet a, .call (.declaration ResidentBigNumeric.naturalCountName), .localSet na,
    .localGet b, .call (.declaration ResidentBigNumeric.naturalCountName), .localSet nb,
    .localGet na, .localGet nb, .i32Add, .localSet capacity] ++
    allocate capacity raw ++ initializePayload ++ [
    .localGet na, .i32Const .uint32 1, .i32Shl, .localSet na,
    .localGet nb, .i32Const .uint32 1, .i32Shl, .localSet nb] ++
    multiply ++ finish }

end Fir.Wasm.Emit.ResidentNatMultiplication
