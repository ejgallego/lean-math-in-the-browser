import Fir.Wasm.Emit.ResidentBigNumeric
import Fir.Wasm.Emit.ResidentCallSite
import Fir.Wasm.Emit.ResidentNatShift
import Fir.Wasm.Emit.ResidentReferenceCount
import Fir.Wasm.Emit.ResidentRelease

namespace Fir.Wasm.Emit.ResidentNatArithmetic

open Fir.Wasm
open Fir.Wasm.Concrete
open Lean
open Lean.Compiler

/-!
# Generic Wasm-resident Nat arithmetic

This family closes the arithmetic frontier exercised by the production
lean-zip Level-1 entry without narrowing Lean Naturals to wasm32. It reuses the
accepted arbitrary-limb resident layout and the existing stack-safe Nat
add/sub/compare helpers. Small 32-bit multiplication takes a direct word path;
larger multiplication and division use structured bit walkers over the same
generic representation.
-/

inductive LinkError where
  | invalidInput (error : SymbolicError)
  | missingHelper (name : Name)
  | reservedDeclaration (name : Name)
  | incompatibleExternal (name : Name)
  | incompatibleMemory
  | invalidOutput (error : SymbolicError)
  | callSite (error : ResidentCallSite.Error)
  deriving Inhabited, Repr

private def u32 (value : Nat) : UInt32 := UInt32.ofNat value

def externalDeclarations : Array Name := #[
  `Nat.mul, `Nat.pow, `Nat.land, `Nat.lor, `Nat.div, `Nat.mod, `Nat.shiftLeft,
  `Int.mul]

def externalName (declaration : Name) : Name :=
  ResidentNumeric.externalName declaration

def externalHelperNames : Array Name := externalDeclarations.map externalName

def mulGenericName : Name := `fir_nat_mul_generic
def divGenericName : Name := `fir_nat_div_generic
def modGenericName : Name := `fir_nat_mod_generic
def internalHelperNames : Array Name := #[mulGenericName, divGenericName, modGenericName]

private def leftParam : FVarId := ⟨`left⟩
private def rightParam : FVarId := ⟨`right⟩
private def valueParam : FVarId := ⟨`value⟩
private def indexParam : FVarId := ⟨`index⟩
private def countParam : FVarId := ⟨`count⟩
private def resultParam : FVarId := ⟨`resultAddress⟩

private def leftCountLocal : FVarId := ⟨`leftCount⟩
private def rightCountLocal : FVarId := ⟨`rightCount⟩
private def countLocal : FVarId := ⟨`countValue⟩
private def indexLocal : FVarId := ⟨`indexValue⟩
private def partCountLocal : FVarId := ⟨`partCount⟩
private def partIndexLocal : FVarId := ⟨`partIndex⟩
private def limbIndexLocal : FVarId := ⟨`limbIndex⟩
private def bitIndexLocal : FVarId := ⟨`bitIndex⟩
private def wordLocal : FVarId := ⟨`word⟩
private def maskLocal : FVarId := ⟨`mask⟩
private def lowLocal : FVarId := ⟨`lowValue⟩
private def highLocal : FVarId := ⟨`highValue⟩
private def leftLowLocal : FVarId := ⟨`leftLow⟩
private def leftHighLocal : FVarId := ⟨`leftHigh⟩
private def rightLowLocal : FVarId := ⟨`rightLow⟩
private def rightHighLocal : FVarId := ⟨`rightHigh⟩
private def carryLocal : FVarId := ⟨`carry⟩
private def lastLocal : FVarId := ⟨`lastNonzero⟩
private def scaledLocal : FVarId := ⟨`scaled⟩
private def rawLocal : FVarId := ⟨`raw⟩
private def raw64Local : FVarId := ⟨`raw64⟩
private def savedScratchLocal : FVarId := ⟨`savedScratch⟩
private def objectResultLocal : FVarId := ⟨`objectResult⟩
private def resultLocal : FVarId := ⟨`resultValue⟩
private def inlineLeftLocal : FVarId := ⟨`_fir_inline_Nat_binary_left⟩
private def inlineRightLocal : FVarId := ⟨`_fir_inline_Nat_binary_right⟩
private def inlineLeftPayloadLocal : FVarId :=
  ⟨`_fir_inline_Nat_binary_left_payload⟩
private def inlineRightPayloadLocal : FVarId :=
  ⟨`_fir_inline_Nat_binary_right_payload⟩
private def inlineProductLocal : FVarId := ⟨`_fir_inline_Nat_mul_product⟩
private def inlineResultLocal : FVarId := ⟨`_fir_inline_Nat_binary_result⟩
private def temporaryLocal : FVarId := ⟨`temporary⟩
private def addendLocal : FVarId := ⟨`addend⟩
private def multiplierLocal : FVarId := ⟨`multiplier⟩
private def factorLocal : FVarId := ⟨`factor⟩
private def remainderLocal : FVarId := ⟨`remainder⟩
private def quotientLocal : FVarId := ⟨`quotient⟩
private def comparisonLocal : FVarId := ⟨`comparison⟩
private def leftSignLocal : FVarId := ⟨`leftSign⟩
private def rightSignLocal : FVarId := ⟨`rightSign⟩
private def resultSignLocal : FVarId := ⟨`resultSign⟩
private def leftNaturalLocal : FVarId := ⟨`leftNatural⟩
private def rightNaturalLocal : FVarId := ⟨`rightNatural⟩
private def productLocal : FVarId := ⟨`product⟩
private def integerLocal : FVarId := ⟨`integerValue⟩

private def mulSmallLoop : FVarId := ⟨`natMulSmallLoop⟩
private def mulPartLoop : FVarId := ⟨`natMulPartLoop⟩
private def mulBitLoop : FVarId := ⟨`natMulBitLoop⟩
private def landScanLoop : FVarId := ⟨`natLandScanLoop⟩
private def landWriteLoop : FVarId := ⟨`natLandWriteLoop⟩
private def lorWriteLoop : FVarId := ⟨`natLorWriteLoop⟩
private def powPartLoop : FVarId := ⟨`natPowPartLoop⟩
private def powBitLoop : FVarId := ⟨`natPowBitLoop⟩
private def divPartLoop : FVarId := ⟨`natDivPartLoop⟩
private def divLeadingLoop : FVarId := ⟨`natDivLeadingLoop⟩
private def divBitLoop : FVarId := ⟨`natDivBitLoop⟩

private def equalsConst (kind : AbiKind) (value : UInt32) : List Instruction :=
  [.i32Const kind value, .i32Eq]

private def trapWhenTrue (condition : List Instruction) : List Instruction :=
  condition ++ [.ifElse [.unreachable] []]

private def scale8 (source destination : FVarId) : List Instruction := [
  .localGet source,
  .localGet source,
  .i32Add,
  .localSet destination,
  .localGet destination,
  .localGet destination,
  .i32Add,
  .localSet destination,
  .localGet destination,
  .localGet destination,
  .i32Add,
  .localSet destination]

private def limbStore (result index scaled value : FVarId) (offset : Nat) :
    List Instruction :=
  scale8 index scaled ++ [
    .localGet result,
    .i32Const .uint32 (u32 headerBytes),
    .i32Add,
    .localGet scaled,
    .i32Add,
    .localGet value,
    .i32Store .uint32 (u32 offset)]

private def retypeRawResult : List Instruction := [
  .localSet rawLocal,
  .i32Const .uint32 0,
  .i32Load .uint32 0,
  .localSet savedScratchLocal,
  .i32Const .uint32 0,
  .localGet rawLocal,
  .i32Store .uint32 0,
  .i32Const .uint32 0,
  .i32Load .tobject 0,
  .localSet objectResultLocal,
  .i32Const .uint32 0,
  .localGet savedScratchLocal,
  .i32Store .uint32 0,
  .localGet objectResultLocal,
  .ret]

private def returnImmediate (word : UInt32) : List Instruction := [
  .i32Const .tobject word,
  .ret]

private def makeNaturalResult (low high : FVarId) : List Instruction := [
  .localGet low,
  .localGet high,
  .call (.declaration ResidentNumeric.makeNaturalName)] ++ retypeRawResult

private def releaseLocal (value : FVarId) : List Instruction :=
  ResidentRelease.checkedDecrementLocal value

private def incrementLocal (value : FVarId) : List Instruction := [
  .localGet value,
  .call (.declaration ResidentReferenceCount.incrementOnceName)]

private def naturalCount (value destination : FVarId) : List Instruction := [
  .localGet value,
  .call (.declaration ResidentBigNumeric.naturalCountName),
  .localSet destination]

private def naturalPart (value part destination : FVarId) : List Instruction := [
  .localGet part,
  .i32Const .uint32 1,
  .i32And,
  .ifElse
    [.localGet value,
      .localGet part,
      .i32Const .uint32 1,
      .i32ShrU,
      .call (.declaration ResidentBigNumeric.naturalHighName),
      .localSet destination]
    [.localGet value,
      .localGet part,
      .i32Const .uint32 1,
      .i32ShrU,
      .call (.declaration ResidentBigNumeric.naturalLowName),
      .localSet destination]]

private def validateInputs : List Instruction := [
  .localGet leftParam,
  .call (.declaration ResidentBigNumeric.validateNaturalName),
  .localGet rightParam,
  .call (.declaration ResidentBigNumeric.validateNaturalName)]

private def addValues (left right destination : FVarId) : List Instruction := [
  .localGet left,
  .localGet right,
  .call (.declaration (ResidentBigNumeric.externalName `Nat.add)),
  .localSet destination]

private def subValues (left right destination : FVarId) : List Instruction := [
  .localGet left,
  .localGet right,
  .call (.declaration (ResidentBigNumeric.externalName `Nat.sub)),
  .localSet destination]

private def compareValues (left right destination : FVarId) : List Instruction := [
  .localGet left,
  .i32Const .uint32 0,
  .localGet right,
  .i32Const .uint32 0,
  .call (.declaration ResidentBigNumeric.compareName),
  .localSet destination]

private def replaceWithSum (target other : FVarId) : List Instruction :=
  addValues target other temporaryLocal ++ releaseLocal target ++ [
    .localGet temporaryLocal,
    .localSet target]

private def doubleLocal (target : FVarId) : List Instruction :=
  replaceWithSum target target

private def smallMulBody : List Instruction := [
  .localGet leftParam,
  .i32Const .uint32 0,
  .call (.declaration ResidentBigNumeric.naturalLowName),
  .localSet leftLowLocal,
  .i32Const .uint32 0,
  .localSet leftHighLocal,
  .localGet rightParam,
  .i32Const .uint32 0,
  .call (.declaration ResidentBigNumeric.naturalLowName),
  .localSet wordLocal,
  .i32Const .uint32 0,
  .localSet lowLocal,
  .i32Const .uint32 0,
  .localSet highLocal,
  .loop mulSmallLoop [
    .localGet wordLocal,
    .i32Const .uint32 0,
    .i32Eq,
    .ifElse (makeNaturalResult lowLocal highLocal) [],
    .localGet wordLocal,
    .i32Const .uint32 1,
    .i32And,
    .ifElse [
      .localGet lowLocal,
      .localGet leftLowLocal,
      .i32Add,
      .localSet rightLowLocal,
      .localGet rightLowLocal,
      .localGet lowLocal,
      .i32LtU,
      .localSet carryLocal,
      .localGet highLocal,
      .localGet leftHighLocal,
      .i32Add,
      .localGet carryLocal,
      .i32Add,
      .localSet highLocal,
      .localGet rightLowLocal,
      .localSet lowLocal] [],
    .localGet wordLocal,
    .i32Const .uint32 1,
    .i32ShrU,
    .localSet wordLocal,
    .localGet leftLowLocal,
    .i32Const .uint32 31,
    .i32ShrU,
    .localSet carryLocal,
    .localGet leftLowLocal,
    .localGet leftLowLocal,
    .i32Add,
    .localSet leftLowLocal,
    .localGet leftHighLocal,
    .localGet leftHighLocal,
    .i32Add,
    .localGet carryLocal,
    .i32Add,
    .localSet leftHighLocal,
    .br mulSmallLoop]]

private def genericMulBit : List Instruction := [
  .localGet wordLocal,
  .i32Const .uint32 1,
  .i32And,
  .ifElse (replaceWithSum resultLocal addendLocal) [],
  .localGet wordLocal,
  .i32Const .uint32 1,
  .i32ShrU,
  .localSet wordLocal] ++ doubleLocal addendLocal ++ [
  .localGet bitIndexLocal,
  .i32Const .uint32 1,
  .i32Add,
  .localSet bitIndexLocal]

private def genericMulBitBody : List Instruction := [
  .localGet bitIndexLocal,
  .i32Const .uint32 32,
  .i32Eq,
  .ifElse [
    .localGet partIndexLocal,
    .i32Const .uint32 1,
    .i32Add,
    .localSet partIndexLocal,
    .br mulPartLoop] []] ++ genericMulBit ++ [.br mulBitLoop]

private def genericMulPartBody : List Instruction := [
  .localGet partIndexLocal,
  .localGet partCountLocal,
  .i32Eq,
  .ifElse (releaseLocal addendLocal ++ [.localGet resultLocal, .ret]) []] ++
  naturalPart multiplierLocal partIndexLocal wordLocal ++ [
  .i32Const .uint32 0,
  .localSet bitIndexLocal,
  .loop mulBitLoop genericMulBitBody]

private def genericMulBody : List Instruction := [
  .localGet leftCountLocal,
  .localGet rightCountLocal,
  .i32LtU,
  .ifElse [
    .localGet rightParam,
    .localSet addendLocal,
    .localGet leftParam,
    .localSet multiplierLocal,
    .localGet leftCountLocal,
    .localSet countLocal] [
    .localGet leftParam,
    .localSet addendLocal,
    .localGet rightParam,
    .localSet multiplierLocal,
    .localGet rightCountLocal,
    .localSet countLocal],
  .localGet addendLocal,
  .call (.declaration ResidentReferenceCount.incrementOnceName),
  .i32Const .tobject 1,
  .localSet resultLocal,
  .i32Const .uint32 0,
  .localSet partIndexLocal,
  .localGet countLocal,
  .localGet countLocal,
  .i32Add,
  .localSet partCountLocal,
  .loop mulPartLoop genericMulPartBody]

def mulGenericFunction : Function := {
  name := mulGenericName
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.tobject]
  locals := #[(leftCountLocal, .uint32), (rightCountLocal, .uint32),
    (countLocal, .uint32), (partCountLocal, .uint32),
    (partIndexLocal, .uint32), (bitIndexLocal, .uint32),
    (wordLocal, .uint32), (resultLocal, .tobject),
    (temporaryLocal, .tobject), (addendLocal, .tobject),
    (multiplierLocal, .tobject)]
  body := validateInputs ++ naturalCount leftParam leftCountLocal ++
    naturalCount rightParam rightCountLocal ++ genericMulBody }

private def callGenericMul : List Instruction := [
  .localGet leftParam,
  .localGet rightParam,
  .call (.declaration mulGenericName),
  .ret]

private def immediateMulBody : List Instruction :=
  ResidentBigNumeric.immediateNaturalPayload leftParam ++ [
    .i64ExtendI32U .uint64] ++
  ResidentBigNumeric.immediateNaturalPayload rightParam ++ [
    .i64ExtendI32U .uint64,
    .i64Mul,
    .localSet raw64Local,
    .localGet raw64Local,
    .i32WrapI64 .uint32,
    .localSet lowLocal,
    .localGet raw64Local,
    .i64Const .uint64 32,
    .i64ShrU,
    .i32WrapI64 .uint32,
    .localSet highLocal] ++
  makeNaturalResult lowLocal highLocal

private def checkedMulBody : List Instruction :=
  validateInputs ++ naturalCount leftParam leftCountLocal ++
    naturalCount rightParam rightCountLocal ++ [
    .localGet leftCountLocal,
    .i32Const .uint32 1,
    .i32Eq,
    .localGet rightCountLocal,
    .i32Const .uint32 1,
    .i32Eq,
    .i32And,
    .ifElse ([
      .localGet leftParam,
      .i32Const .uint32 0,
      .call (.declaration ResidentBigNumeric.naturalHighName),
      .i32Const .uint32 0,
      .i32Eq,
      .localGet rightParam,
      .i32Const .uint32 0,
      .call (.declaration ResidentBigNumeric.naturalHighName),
      .i32Const .uint32 0,
      .i32Eq,
      .i32And,
      .ifElse smallMulBody callGenericMul]) callGenericMul]

def mulFunction : Function := {
  name := externalName `Nat.mul
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.tobject]
  locals := #[(leftCountLocal, .uint32), (rightCountLocal, .uint32),
    (countLocal, .uint32), (partCountLocal, .uint32),
    (partIndexLocal, .uint32), (bitIndexLocal, .uint32),
    (wordLocal, .uint32), (leftLowLocal, .uint32),
    (leftHighLocal, .uint32), (rightLowLocal, .uint32),
    (lowLocal, .uint32), (highLocal, .uint32), (carryLocal, .uint32),
    (resultLocal, .tobject), (temporaryLocal, .tobject),
    (addendLocal, .tobject), (multiplierLocal, .tobject),
    (rawLocal, .uint32), (raw64Local, .uint64),
    (savedScratchLocal, .uint32),
    (objectResultLocal, .tobject)]
  body := ResidentBigNumeric.withImmediateNaturalPair leftParam rightParam
    immediateMulBody checkedMulBody }

def intMulFunction : Function := {
  name := externalName `Int.mul
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.tobject]
  locals := #[(leftSignLocal, .uint32), (rightSignLocal, .uint32),
    (resultSignLocal, .uint32), (leftNaturalLocal, .tobject),
    (rightNaturalLocal, .tobject), (productLocal, .tobject),
    (integerLocal, .tobject), (resultLocal, .tobject)]
  body := [
    .localGet leftParam,
    .call (.declaration ResidentBigNumeric.validateIntegerName),
    .localGet rightParam,
    .call (.declaration ResidentBigNumeric.validateIntegerName),
    .localGet leftParam,
    .call (.declaration ResidentBigNumeric.integerSignName),
    .localSet leftSignLocal,
    .localGet rightParam,
    .call (.declaration ResidentBigNumeric.integerSignName),
    .localSet rightSignLocal,
    .localGet leftSignLocal,
    .localGet rightSignLocal,
    .i32Xor,
    .localSet resultSignLocal,
    .localGet leftParam,
    .call (.declaration (ResidentBigNumeric.externalName `Int.natAbs)),
    .localSet leftNaturalLocal,
    .localGet rightParam,
    .call (.declaration (ResidentBigNumeric.externalName `Int.natAbs)),
    .localSet rightNaturalLocal,
    .localGet leftNaturalLocal,
    .localGet rightNaturalLocal,
    .call (.declaration (externalName `Nat.mul)),
    .localSet productLocal] ++
    releaseLocal leftNaturalLocal ++ releaseLocal rightNaturalLocal ++ [
    .localGet productLocal,
    .call (.declaration (ResidentBigNumeric.externalName `Int.ofNat)),
    .localSet integerLocal] ++
    releaseLocal productLocal ++ [
    .localGet resultSignLocal,
    .ifElse
      ([.localGet integerLocal,
          .call (.declaration (ResidentBigNumeric.externalName `Int.neg)),
          .localSet resultLocal] ++
        releaseLocal integerLocal)
      [.localGet integerLocal,
        .localSet resultLocal],
    .localGet resultLocal,
    .ret] }

private def landParts : List Instruction := [
  .localGet leftParam,
  .localGet indexLocal,
  .call (.declaration ResidentBigNumeric.naturalLowName),
  .localGet rightParam,
  .localGet indexLocal,
  .call (.declaration ResidentBigNumeric.naturalLowName),
  .i32And,
  .localSet lowLocal,
  .localGet leftParam,
  .localGet indexLocal,
  .call (.declaration ResidentBigNumeric.naturalHighName),
  .localGet rightParam,
  .localGet indexLocal,
  .call (.declaration ResidentBigNumeric.naturalHighName),
  .i32And,
  .localSet highLocal]

private def allocateNatural : List Instruction := [
  .i32Const .uint32 ObjectKind.natural.code,
  .i32Const .uint32 bigNaturalMarker,
  .i32Const .uint32 0,
  .localGet lastLocal,
  .call (.declaration ResidentBigNumeric.allocateName),
  .localSet rawLocal]

private def landWriteBody : List Instruction := [
  .localGet indexLocal,
  .localGet lastLocal,
  .i32Eq,
  .ifElse ([.localGet rawLocal] ++ retypeRawResult) []] ++ landParts ++
  limbStore rawLocal indexLocal scaledLocal lowLocal 0 ++
  limbStore rawLocal indexLocal scaledLocal highLocal 4 ++ [
  .localGet indexLocal,
  .i32Const .uint32 1,
  .i32Add,
  .localSet indexLocal,
  .br landWriteLoop]

private def landFinish : List Instruction := [
  .localGet lastLocal,
  .i32Const .uint32 0,
  .i32Eq,
  .ifElse (returnImmediate 1) [],
  .localGet lastLocal,
  .i32Const .uint32 1,
  .i32Eq,
  .ifElse ([.i32Const .uint32 0, .localSet indexLocal] ++ landParts ++
    makeNaturalResult lowLocal highLocal) [],
  .i32Const .uint32 0,
  .localSet indexLocal] ++ allocateNatural ++ [
  .loop landWriteLoop landWriteBody]

private def landScanBody : List Instruction := [
  .localGet indexLocal,
  .localGet countLocal,
  .i32Eq,
  .ifElse landFinish []] ++ landParts ++ [
  .localGet lowLocal,
  .i32Const .uint32 0,
  .i32Eq,
  .localGet highLocal,
  .i32Const .uint32 0,
  .i32Eq,
  .i32And,
  .ifElse [] [
    .localGet indexLocal,
    .i32Const .uint32 1,
    .i32Add,
    .localSet lastLocal],
  .localGet indexLocal,
  .i32Const .uint32 1,
  .i32Add,
  .localSet indexLocal,
  .br landScanLoop]

def landFunction : Function := {
  name := externalName `Nat.land
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.tobject]
  locals := #[(leftCountLocal, .uint32), (rightCountLocal, .uint32),
    (countLocal, .uint32), (indexLocal, .uint32), (lastLocal, .uint32),
    (lowLocal, .uint32), (highLocal, .uint32), (scaledLocal, .uint32),
    (rawLocal, .uint32), (savedScratchLocal, .uint32),
    (objectResultLocal, .tobject)]
  body := validateInputs ++ naturalCount leftParam leftCountLocal ++
    naturalCount rightParam rightCountLocal ++ [
    .localGet leftCountLocal,
    .localGet rightCountLocal,
    .i32LtU,
    .ifElse [.localGet leftCountLocal, .localSet countLocal]
      [.localGet rightCountLocal, .localSet countLocal],
    .i32Const .uint32 0,
    .localSet indexLocal,
    .i32Const .uint32 0,
    .localSet lastLocal,
    .loop landScanLoop landScanBody] }

/- `naturalLow` and `naturalHigh` deliberately assume a valid limb index for
heap-backed values.  Unlike `Nat.land`, OR walks the larger operand, so each
load must be guarded by that operand's actual limb count. -/
private def lorParts : List Instruction := [
  .localGet indexLocal,
  .localGet leftCountLocal,
  .i32LtU,
  .ifElse
    [.localGet leftParam,
      .localGet indexLocal,
      .call (.declaration ResidentBigNumeric.naturalLowName),
      .localSet leftLowLocal]
    [.i32Const .uint32 0, .localSet leftLowLocal],
  .localGet indexLocal,
  .localGet rightCountLocal,
  .i32LtU,
  .ifElse
    [.localGet rightParam,
      .localGet indexLocal,
      .call (.declaration ResidentBigNumeric.naturalLowName),
      .localSet rightLowLocal]
    [.i32Const .uint32 0, .localSet rightLowLocal],
  .localGet leftLowLocal,
  .localGet rightLowLocal,
  .i32Or,
  .localSet lowLocal,
  .localGet indexLocal,
  .localGet leftCountLocal,
  .i32LtU,
  .ifElse
    [.localGet leftParam,
      .localGet indexLocal,
      .call (.declaration ResidentBigNumeric.naturalHighName),
      .localSet leftHighLocal]
    [.i32Const .uint32 0, .localSet leftHighLocal],
  .localGet indexLocal,
  .localGet rightCountLocal,
  .i32LtU,
  .ifElse
    [.localGet rightParam,
      .localGet indexLocal,
      .call (.declaration ResidentBigNumeric.naturalHighName),
      .localSet rightHighLocal]
    [.i32Const .uint32 0, .localSet rightHighLocal],
  .localGet leftHighLocal,
  .localGet rightHighLocal,
  .i32Or,
  .localSet highLocal]

private def lorWriteBody : List Instruction := [
  .localGet indexLocal,
  .localGet lastLocal,
  .i32Eq,
  .ifElse ([.localGet rawLocal] ++ retypeRawResult) []] ++ lorParts ++
  limbStore rawLocal indexLocal scaledLocal lowLocal 0 ++
  limbStore rawLocal indexLocal scaledLocal highLocal 4 ++ [
  .localGet indexLocal,
  .i32Const .uint32 1,
  .i32Add,
  .localSet indexLocal,
  .br lorWriteLoop]

def lorFunction : Function := {
  name := externalName `Nat.lor
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.tobject]
  locals := #[(leftCountLocal, .uint32), (rightCountLocal, .uint32),
    (indexLocal, .uint32), (lastLocal, .uint32),
    (leftLowLocal, .uint32), (leftHighLocal, .uint32),
    (rightLowLocal, .uint32), (rightHighLocal, .uint32),
    (lowLocal, .uint32), (highLocal, .uint32), (scaledLocal, .uint32),
    (rawLocal, .uint32), (savedScratchLocal, .uint32),
    (objectResultLocal, .tobject)]
  body := validateInputs ++ naturalCount leftParam leftCountLocal ++
    naturalCount rightParam rightCountLocal ++ [
    .localGet leftCountLocal,
    .localGet rightCountLocal,
    .i32GtU,
    .ifElse [.localGet leftCountLocal, .localSet lastLocal]
      [.localGet rightCountLocal, .localSet lastLocal],
    .localGet lastLocal,
    .i32Const .uint32 1,
    .i32Eq,
    .ifElse ([.i32Const .uint32 0, .localSet indexLocal] ++ lorParts ++
      makeNaturalResult lowLocal highLocal) [],
    .i32Const .uint32 0,
    .localSet indexLocal] ++ allocateNatural ++ [
    .loop lorWriteLoop lorWriteBody] }

private def computePartCount (value count : FVarId) : List Instruction := [
  .localGet count,
  .localGet count,
  .i32Add,
  .localSet partCountLocal,
  .localGet value,
  .localGet count,
  .i32Const .uint32 1,
  .i32Sub,
  .call (.declaration ResidentBigNumeric.naturalHighName),
  .i32Const .uint32 0,
  .i32Eq,
  .ifElse [
    .localGet partCountLocal,
    .i32Const .uint32 1,
    .i32Sub,
    .localSet partCountLocal] []]

private def replaceWithProduct (target other : FVarId) : List Instruction := [
  .localGet target,
  .localGet other,
  .call (.declaration (externalName `Nat.mul)),
  .localSet temporaryLocal] ++ releaseLocal target ++ [
  .localGet temporaryLocal,
  .localSet target]

private def powFinish : List Instruction :=
  releaseLocal factorLocal ++ [.localGet resultLocal, .ret]

private def powBitBody : List Instruction := [
  .localGet partIndexLocal,
  .i32Const .uint32 1,
  .i32Add,
  .localGet partCountLocal,
  .i32Eq,
  .localGet wordLocal,
  .i32Const .uint32 0,
  .i32Eq,
  .i32And,
  .ifElse powFinish [],
  .localGet bitIndexLocal,
  .i32Const .uint32 32,
  .i32Eq,
  .ifElse [
    .localGet partIndexLocal,
    .i32Const .uint32 1,
    .i32Add,
    .localSet partIndexLocal,
    .br powPartLoop] [],
  .localGet wordLocal,
  .i32Const .uint32 1,
  .i32And,
  .ifElse (replaceWithProduct resultLocal factorLocal) [],
  .localGet wordLocal,
  .i32Const .uint32 1,
  .i32ShrU,
  .localSet wordLocal,
  .localGet partIndexLocal,
  .i32Const .uint32 1,
  .i32Add,
  .localGet partCountLocal,
  .i32Eq,
  .localGet wordLocal,
  .i32Const .uint32 0,
  .i32Eq,
  .i32And,
  .ifElse powFinish [],
  .localGet factorLocal,
  .localGet factorLocal,
  .call (.declaration (externalName `Nat.mul)),
  .localSet temporaryLocal] ++ releaseLocal factorLocal ++ [
  .localGet temporaryLocal,
  .localSet factorLocal,
  .localGet bitIndexLocal,
  .i32Const .uint32 1,
  .i32Add,
  .localSet bitIndexLocal,
  .br powBitLoop]

private def powPartBody : List Instruction := [
  .localGet partIndexLocal,
  .localGet partCountLocal,
  .i32Eq,
  .ifElse powFinish []] ++ naturalPart rightParam partIndexLocal wordLocal ++ [
  .i32Const .uint32 0,
  .localSet bitIndexLocal,
  .loop powBitLoop powBitBody]

def powFunction : Function := {
  name := externalName `Nat.pow
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.tobject]
  locals := #[(rightCountLocal, .uint32), (partCountLocal, .uint32),
    (partIndexLocal, .uint32), (bitIndexLocal, .uint32),
    (wordLocal, .uint32), (resultLocal, .tobject),
    (factorLocal, .tobject), (temporaryLocal, .tobject)]
  body := validateInputs ++ naturalCount rightParam rightCountLocal ++ [
    .i32Const .tobject 3,
    .localSet resultLocal,
    .localGet leftParam,
    .localSet factorLocal] ++ incrementLocal factorLocal ++
    computePartCount rightParam rightCountLocal ++ [
    .i32Const .uint32 0,
    .localSet partIndexLocal,
    .loop powPartLoop powPartBody] }

/-- Exact arbitrary-precision left shift, expressed through the already
resident generic arithmetic rather than a bounded machine-word shortcut. -/
def shiftLeftFunction : Function := {
  name := externalName `Nat.shiftLeft
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.tobject]
  locals := #[(factorLocal, .tobject), (resultLocal, .tobject)]
  body := [
    .i32Const .tobject 5,
    .localGet rightParam,
    .call (.declaration (externalName `Nat.pow)),
    .localSet factorLocal,
    .localGet leftParam,
    .localGet factorLocal,
    .call (.declaration (externalName `Nat.mul)),
    .localSet resultLocal] ++ releaseLocal factorLocal ++ [
    .localGet resultLocal,
    .ret] }

private def genericDivStep : List Instruction :=
  doubleLocal remainderLocal ++ [
  .localGet wordLocal,
  .localGet maskLocal,
  .i32And,
  .i32Const .uint32 0,
  .i32Eq,
  .ifElse [] (replaceWithSum remainderLocal resultParam)] ++
  doubleLocal quotientLocal ++ compareValues remainderLocal rightParam comparisonLocal ++ [
  .localGet comparisonLocal,
  .i32Const .uint32 1,
  .i32Eq,
  .ifElse [] (subValues remainderLocal rightParam temporaryLocal ++
    releaseLocal remainderLocal ++ [
      .localGet temporaryLocal,
      .localSet remainderLocal] ++ replaceWithSum quotientLocal resultParam)] ++ [
  .localGet maskLocal,
  .i32Const .uint32 1,
  .i32ShrU,
  .localSet maskLocal]

private def divFinish : List Instruction :=
  releaseLocal remainderLocal ++ [.localGet quotientLocal, .ret]

private def modFinish : List Instruction :=
  releaseLocal quotientLocal ++ [.localGet remainderLocal, .ret]

private def divLeadingBody (finish : List Instruction) : List Instruction := [
  .localGet wordLocal,
  .localGet maskLocal,
  .i32And,
  .i32Const .uint32 0,
  .i32Eq,
  .ifElse [
    .localGet maskLocal,
    .i32Const .uint32 1,
    .i32ShrU,
    .localSet maskLocal,
    .localGet maskLocal,
    .i32Const .uint32 0,
    .i32Eq,
    .ifElse finish [],
    .br divLeadingLoop] []]

private def divBitBody : List Instruction := [
  .localGet maskLocal,
  .i32Const .uint32 0,
  .i32Eq,
  .ifElse [.br divPartLoop] []] ++ genericDivStep ++ [.br divBitLoop]

private def divPartBody (finish : List Instruction) : List Instruction := [
  .localGet partIndexLocal,
  .i32Const .uint32 0,
  .i32Eq,
  .ifElse finish [],
  .localGet partIndexLocal,
  .i32Const .uint32 1,
  .i32Sub,
  .localSet partIndexLocal] ++ naturalPart leftParam partIndexLocal wordLocal ++ [
  .i32Const .uint32 2147483648,
  .localSet maskLocal,
  .localGet partIndexLocal,
  .i32Const .uint32 1,
  .i32Add,
  .localGet partCountLocal,
  .i32Eq,
  .ifElse [.loop divLeadingLoop (divLeadingBody finish)] [],
  .loop divBitLoop divBitBody]

private def genericDivBody (finish : List Instruction) : List Instruction := [
  .i32Const .tobject 1,
  .localSet remainderLocal,
  .i32Const .tobject 1,
  .localSet quotientLocal,
  .i32Const .tobject 3,
  .localSet resultParam] ++ computePartCount leftParam leftCountLocal ++ [
  .localGet partCountLocal,
  .localSet partIndexLocal,
  .loop divPartLoop (divPartBody finish)]

def divGenericFunction : Function := {
  name := divGenericName
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.tobject]
  locals := #[(leftCountLocal, .uint32), (partCountLocal, .uint32),
    (partIndexLocal, .uint32), (wordLocal, .uint32),
    (maskLocal, .uint32), (remainderLocal, .tobject),
    (quotientLocal, .tobject), (resultParam, .tobject),
    (temporaryLocal, .tobject), (comparisonLocal, .uint32)]
  body := validateInputs ++ naturalCount leftParam leftCountLocal ++ genericDivBody divFinish }

def modGenericFunction : Function := {
  name := modGenericName
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.tobject]
  locals := #[(leftCountLocal, .uint32), (partCountLocal, .uint32),
    (partIndexLocal, .uint32), (wordLocal, .uint32),
    (maskLocal, .uint32), (remainderLocal, .tobject),
    (quotientLocal, .tobject), (resultParam, .tobject),
    (temporaryLocal, .tobject), (comparisonLocal, .uint32)]
  body := validateInputs ++ naturalCount leftParam leftCountLocal ++ genericDivBody modFinish }

private def callGenericDiv : List Instruction := [
  .localGet leftParam,
  .localGet rightParam,
  .call (.declaration divGenericName),
  .ret]

private def callGenericMod : List Instruction := [
  .localGet leftParam,
  .localGet rightParam,
  .call (.declaration modGenericName),
  .ret]

/-- The canonical two-immediate remainder path.  A zero divisor returns the
already-canonical left word.  Otherwise the machine remainder is strictly
smaller than the 31-bit immediate divisor, so `makeNatural` returns an
immediate without allocation. -/
private def immediateMod : List Instruction :=
  ResidentBigNumeric.immediateNaturalPayload rightParam ++ [
    .i32Const .uint32 0,
    .i32Eq,
    .ifElse
      [.localGet leftParam, .ret]
      (ResidentBigNumeric.immediateNaturalPayload leftParam ++
        ResidentBigNumeric.immediateNaturalPayload rightParam ++ [
          .i32RemU,
          .i32Const .uint32 0,
          .call (.declaration ResidentNumeric.makeNaturalName)] ++
        retypeRawResult)]

/-- The pre-existing checked arbitrary-precision implementation, retained as
the exact fallback for mixed and heap-backed representations. -/
private def checkedModFallback : List Instruction := validateInputs ++ [
  .localGet rightParam,
  .i32Const .uint32 0,
  .call (.declaration ResidentBigNumeric.naturalLowName),
  .i32Const .uint32 0,
  .i32Eq,
  .localGet rightParam,
  .i32Const .uint32 0,
  .call (.declaration ResidentBigNumeric.naturalHighName),
  .i32Const .uint32 0,
  .i32Eq,
  .i32And,
  .ifElse (incrementLocal leftParam ++ [.localGet leftParam, .ret]) callGenericMod]

def divFunction : Function := {
  name := externalName `Nat.div
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.tobject]
  locals := #[]
  body := validateInputs ++ [
    .localGet rightParam,
    .i32Const .uint32 0,
    .call (.declaration ResidentBigNumeric.naturalLowName),
    .i32Const .uint32 0,
    .i32Eq,
    .localGet rightParam,
    .i32Const .uint32 0,
    .call (.declaration ResidentBigNumeric.naturalHighName),
    .i32Const .uint32 0,
    .i32Eq,
    .i32And,
    .ifElse (returnImmediate 1) callGenericDiv] }

def modFunction : Function := {
  name := externalName `Nat.mod
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.tobject]
  locals := #[(rawLocal, .uint32), (savedScratchLocal, .uint32),
    (objectResultLocal, .tobject)]
  body := ResidentBigNumeric.withImmediateNaturalPair leftParam rightParam
    immediateMod checkedModFallback }

private def retypeTaggedWord : List Instruction := [
  .i64ExtendI32U .uint64,
  .i32WrapI64 .tagged]

private def boxImmediatePayload : List Instruction := [
  .i64ExtendI32U .uint64,
  .i64Const .uint64 1,
  .i64Shl,
  .i64Const .uint64 1,
  .i64Or,
  .i32WrapI64 .tagged]

private def binaryImmediateTest : List Instruction := [
  .localGet inlineLeftLocal,
  .i32Const .uint32 1,
  .i32And,
  .localGet inlineRightLocal,
  .i32Const .uint32 1,
  .i32And,
  .i32And]

private def binaryFallback (helper : Name) : List Instruction := [
  .localGet inlineLeftLocal,
  .localGet inlineRightLocal,
  .call (.declaration helper),
  .localSet inlineResultLocal]

private def binaryPrefix : List Instruction := [
  .localSet inlineRightLocal,
  .localSet inlineLeftLocal]

private def landCallSiteRewrite : ResidentCallSite.Rewrite := {
  target := .declaration `Nat.land
  signature := { params := #[.tobject, .tobject], results := #[.tobject] }
  locals := #[(inlineLeftLocal, .tobject), (inlineRightLocal, .tobject),
    (inlineResultLocal, .tobject)]
  /- `Nat.land left right ≤ right`. A tagged right operand therefore bounds
  the result by the complete immediate payload range, even when the left
  operand takes the arbitrary-precision fallback. `landFunction` constructs
  its one-limb result through `makeNatural`, which preserves this canonical
  tagged representation. -/
  conditionalResultRefinement? := some {
    argumentKinds := #[none, some .tagged]
    kind := .tagged }
  body := binaryPrefix ++ binaryImmediateTest ++ [
    .ifElse
      ([.localGet inlineLeftLocal,
        .localGet inlineRightLocal,
        .i32And] ++ retypeTaggedWord ++ [
        .localSet inlineResultLocal])
      (binaryFallback (externalName `Nat.land)),
    .localGet inlineResultLocal] }

private def modCallSiteRewrite : ResidentCallSite.Rewrite := {
  target := .declaration `Nat.mod
  signature := { params := #[.tobject, .tobject], results := #[.tobject] }
  locals := #[(inlineLeftLocal, .tobject), (inlineRightLocal, .tobject),
    (inlineLeftPayloadLocal, .uint32), (inlineRightPayloadLocal, .uint32),
    (inlineResultLocal, .tobject)]
  body := binaryPrefix ++ binaryImmediateTest ++ [
    .ifElse
      (ResidentBigNumeric.immediateNaturalPayload inlineRightLocal ++ [
        .localSet inlineRightPayloadLocal,
        .localGet inlineRightPayloadLocal,
        .i32Eqz,
        .ifElse
          [.localGet inlineLeftLocal,
            .localSet inlineResultLocal]
          (ResidentBigNumeric.immediateNaturalPayload inlineLeftLocal ++ [
            .localSet inlineLeftPayloadLocal,
            .localGet inlineLeftPayloadLocal,
            .localGet inlineRightPayloadLocal,
            .i32RemU] ++ boxImmediatePayload ++ [
            .localSet inlineResultLocal])])
      (binaryFallback (externalName `Nat.mod)),
    .localGet inlineResultLocal] }

private def mulCallSiteRewrite : ResidentCallSite.Rewrite := {
  target := .declaration `Nat.mul
  signature := { params := #[.tobject, .tobject], results := #[.tobject] }
  locals := #[(inlineLeftLocal, .tobject), (inlineRightLocal, .tobject),
    (inlineProductLocal, .uint64), (inlineResultLocal, .tobject)]
  body := binaryPrefix ++ binaryImmediateTest ++ [
    .ifElse
      (ResidentBigNumeric.immediateNaturalPayload inlineLeftLocal ++ [
        .i64ExtendI32U .uint64] ++
        ResidentBigNumeric.immediateNaturalPayload inlineRightLocal ++ [
        .i64ExtendI32U .uint64,
        .i64Mul,
        .localSet inlineProductLocal,
        .localGet inlineProductLocal,
        .i64Const .uint64 2147483648,
        .i64LtU,
        .ifElse
          [.localGet inlineProductLocal,
            .i64Const .uint64 1,
            .i64Shl,
            .i64Const .uint64 1,
            .i64Or,
            .i32WrapI64 .tagged,
            .localSet inlineResultLocal]
          (binaryFallback (externalName `Nat.mul))])
      (binaryFallback (externalName `Nat.mul)),
    .localGet inlineResultLocal] }

/-- Upstream-shaped scalar gates for the profiled Nat bitwise/remainder
operations. Heap-backed pairs retain the complete resident helpers. -/
def callSiteRewrites : Array ResidentCallSite.Rewrite := #[
  landCallSiteRewrite,
  modCallSiteRewrite,
  mulCallSiteRewrite]

private partial def callSiteContains (needle : Instruction) :
    Instruction → Bool
  | .block _ body | .loop _ body => body.any (callSiteContains needle)
  | .ifElse thenBody elseBody =>
      thenBody.any (callSiteContains needle) ||
        elseBody.any (callSiteContains needle)
  | instruction => instruction == needle

#guard landCallSiteRewrite.locals.size == 3
#guard modCallSiteRewrite.locals.size == 5
#guard mulCallSiteRewrite.locals.size == 4
#guard landCallSiteRewrite.conditionalResultRefinement? == some {
  argumentKinds := #[none, some .tagged]
  kind := .tagged }
#guard landCallSiteRewrite.body.any (callSiteContains .i32And)
#guard modCallSiteRewrite.body.any (callSiteContains .i32RemU)
#guard mulCallSiteRewrite.body.any (callSiteContains .i64Mul)

def externalFunctions : Array Function := #[
  mulFunction, powFunction, landFunction, lorFunction, divFunction, modFunction,
  shiftLeftFunction, intMulFunction]

def internalFunctions : Array Function := #[
  mulGenericFunction, divGenericFunction, modGenericFunction]

private partial def rewriteInstruction : Instruction → Instruction
  | .call (.declaration declaration) =>
      if externalDeclarations.contains declaration then
        .call (.declaration (externalName declaration))
      else .call (.declaration declaration)
  | .block label body => .block label (body.map rewriteInstruction)
  | .loop label body => .loop label (body.map rewriteInstruction)
  | .ifElse thenBody elseBody =>
      .ifElse (thenBody.map rewriteInstruction) (elseBody.map rewriteInstruction)
  | instruction => instruction

private def requiredHelpers : Array Name := #[
  ResidentBigNumeric.validateNaturalName,
  ResidentBigNumeric.naturalCountName,
  ResidentBigNumeric.naturalLowName,
  ResidentBigNumeric.naturalHighName,
  ResidentBigNumeric.allocateName,
  ResidentBigNumeric.compareName,
  ResidentBigNumeric.externalName `Nat.add,
  ResidentBigNumeric.externalName `Nat.sub,
  ResidentNumeric.makeNaturalName,
  ResidentReferenceCount.incrementOnceName,
  ResidentRelease.decrementOnceName]

def internalizeAvailable (module : Module) (validate : Bool := true) :
    Except LinkError Module := do
  if validate then
    match Fir.Wasm.validateModule module with
    | .ok () => pure ()
    | .error error => throw (.invalidInput error)
  unless module.memory == some ResidentRuntime.residentMemory do
    throw .incompatibleMemory
  let present := externalDeclarations.filter fun declaration =>
    module.imports.any (·.declaration? == some declaration)
  if present.isEmpty then return module
  for helper in requiredHelpers do
    unless module.functions.any (·.name == helper) do
      throw (.missingHelper helper)
  for declaration in present do
    let imports := module.imports.filter (·.declaration? == some declaration)
    unless imports.size == 1 && imports[0]!.signature == {
        params := #[.tobject, .tobject], results := #[.tobject] } do
      throw (.incompatibleExternal declaration)
    let helper := externalName declaration
    if module.imports.any (·.declaration? == some helper) ||
        module.functions.any (·.name == helper) || module.exports.contains helper then
      throw (.reservedDeclaration helper)
  let selectedExternalFunctions := externalFunctions.filter fun function =>
    present.any fun declaration => externalName declaration == function.name
  let needsMul := present.contains `Nat.pow || present.contains `Nat.shiftLeft ||
    present.contains `Int.mul
  let needsPow := present.contains `Nat.shiftLeft
  let selectedExternalFunctions :=
    if needsMul && !selectedExternalFunctions.any (·.name == mulFunction.name) then
      selectedExternalFunctions.push mulFunction
    else selectedExternalFunctions
  let selectedExternalFunctions :=
    if needsPow && !selectedExternalFunctions.any (·.name == powFunction.name) then
      selectedExternalFunctions.push powFunction
    else selectedExternalFunctions
  let selectedInternalFunctions := internalFunctions.filter fun function =>
    (function.name == mulGenericName &&
      (present.contains `Nat.mul || present.contains `Nat.pow ||
        present.contains `Nat.shiftLeft || present.contains `Int.mul)) ||
    (function.name == divGenericName && present.contains `Nat.div) ||
    (function.name == modGenericName && present.contains `Nat.mod)
  for function in selectedInternalFunctions do
    if module.imports.any (·.declaration? == some function.name) ||
        module.functions.any (·.name == function.name) ||
        module.exports.contains function.name then
      throw (.reservedDeclaration function.name)
  let callerRewrites := callSiteRewrites.filter fun rewrite =>
    match rewrite.target with
    | .declaration declaration => present.contains declaration
    | .runtime _ => false
  let callerRewritten ←
    ResidentCallSite.rewriteModuleFunctions callerRewrites module
      |>.mapError LinkError.callSite
  let functions := callerRewritten.map fun function =>
    { function with body := function.body.map rewriteInstruction }
  let functions := functions ++ selectedInternalFunctions ++ selectedExternalFunctions
  let result : Module := {
    module with
    imports := module.imports.filter fun import_ =>
      match import_.declaration? with
      | some declaration => !present.contains declaration
      | none => true
    functions
    exports := present.foldl
      (fun exports declaration =>
        Fir.Wasm.addUnique exports (externalName declaration))
      module.exports
    runtimeOperations := Fir.Wasm.collectRuntimeOps functions }
  if validate then
    match Fir.Wasm.validateModule result with
    | .ok () => return result
    | .error error => throw (.invalidOutput error)
  else return result

private def exampleImport (declaration : Name) : Import := {
  key := .external declaration
  moduleName := "lean.extern"
  itemName := declaration.toString
  signature := { params := #[.tobject, .tobject], results := #[.tobject] }
  externalTypes? := some {
    params := #[LCNF.ImpureType.tobject, LCNF.ImpureType.tobject]
    result := LCNF.ImpureType.tobject } }

private def log2ExampleImport : Import := {
  key := .external ResidentNatShift.log2Declaration
  moduleName := "lean.extern"
  itemName := ResidentNatShift.log2Declaration.toString
  signature := { params := #[.tobject], results := #[.tobject] }
  externalTypes? := some {
    params := #[LCNF.ImpureType.tobject]
    result := LCNF.ImpureType.tobject } }

private def shiftRightCallerName : Name := `fir_example_Nat_shiftRightCaller
private def landCallerName : Name := `fir_example_Nat_landCaller
private def modCallerName : Name := `fir_example_Nat_modCaller
private def mulCallerName : Name := `fir_example_Nat_mulCaller

/-- A real compiled caller retained by the resident artifact so the linker
call-site rewrite is exercised by an external engine rather than only inspected
as symbolic instructions. -/
private def shiftRightCallerFunction : Function := {
  name := shiftRightCallerName
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.tobject]
  locals := #[]
  body := [
    .localGet leftParam,
    .localGet rightParam,
    .call (.declaration ResidentNatShift.declaration),
    .ret] }

private def binaryCallerFunction (name declaration : Name) : Function := {
  name
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.tobject]
  locals := #[]
  body := [
    .localGet leftParam,
    .localGet rightParam,
    .call (.declaration declaration),
    .ret] }

private def landCallerFunction : Function :=
  binaryCallerFunction landCallerName `Nat.land

private def modCallerFunction : Function :=
  binaryCallerFunction modCallerName `Nat.mod

private def mulCallerFunction : Function :=
  binaryCallerFunction mulCallerName `Nat.mul

def residentExampleModule : Except String Module := do
  let module ← ResidentBigNumeric.residentExampleModule
  let module ← ResidentReferenceCount.internalizeIncrements module
    |>.mapError fun error => s!"increments: {repr error}"
  let module ← ResidentRelease.internalizeReleases module
    |>.mapError fun error => s!"releases: {repr error}"
  let module := { module with
    imports := module.imports ++ externalDeclarations.map exampleImport ++
      #[exampleImport ResidentNatShift.declaration, log2ExampleImport]
    functions := module.functions ++ #[shiftRightCallerFunction,
      landCallerFunction, modCallerFunction, mulCallerFunction]
    exports := (#[shiftRightCallerName, landCallerName, modCallerName,
      mulCallerName]).foldl Fir.Wasm.addUnique module.exports }
  let module ← internalizeAvailable module
    |>.mapError fun error => s!"Nat arithmetic: {repr error}"
  ResidentNatShift.internalizeAvailable module
    |>.mapError fun error => s!"Nat shift: {repr error}"

private def manifestEntries : Array Json :=
  let entries := (externalDeclarations.push ResidentNatShift.declaration).map
    fun declaration => Json.mkObj [
      ("entry", externalName declaration |>.toString),
      ("params", Json.arr #["tobject", "tobject"]),
      ("result", "tobject")]
  entries ++ #[
    Json.mkObj [
      ("entry", ResidentNatShift.log2HelperName.toString),
      ("params", Json.arr #["tobject"]),
      ("result", "tobject")],
    Json.mkObj [
      ("entry", shiftRightCallerName.toString),
      ("params", Json.arr #["tobject", "tobject"]),
      ("result", "tobject")],
    Json.mkObj [
      ("entry", landCallerName.toString),
      ("params", Json.arr #["tobject", "tobject"]),
      ("result", "tobject")],
    Json.mkObj [
      ("entry", modCallerName.toString),
      ("params", Json.arr #["tobject", "tobject"]),
      ("result", "tobject")],
    Json.mkObj [
      ("entry", mulCallerName.toString),
      ("params", Json.arr #["tobject", "tobject"]),
      ("result", "tobject")]]

def manifest : Json := Json.mkObj [
  ("sourceEntry", `Nat.mul |>.toString),
  ("entry", externalName `Nat.mul |>.toString),
  ("params", Json.arr #["tobject", "tobject"]),
  ("result", "tobject"),
  ("closureDispatch", Json.arr #[]),
  ("closureDescriptors", Json.arr #[]),
  ("entries", Json.arr manifestEntries),
  ("imports", Json.arr #[]),
  ("numericLimbBits", 64),
  ("walkerControl", "structured-loop"),
  ("status", "generation-only; W6 generic Nat contract proofs pending")]

#guard match residentExampleModule with
  | .ok module =>
      match module.functions.find? (·.name == shiftRightCallerName) with
      | some caller =>
          caller.locals.size == 4 && caller.body != shiftRightCallerFunction.body
      | none => false
  | .error _ => false

#guard match residentExampleModule with
  | .ok module =>
      match module.functions.find? (·.name == landCallerName),
          module.functions.find? (·.name == modCallerName),
          module.functions.find? (·.name == mulCallerName) with
      | some landCaller, some modCaller, some mulCaller =>
          landCaller.locals.size == 3 && modCaller.locals.size == 5 &&
            mulCaller.locals.size == 4 &&
            landCaller.body != landCallerFunction.body &&
            modCaller.body != modCallerFunction.body &&
            mulCaller.body != mulCallerFunction.body
      | _, _, _ => false
  | .error _ => false

#guard match residentExampleModule with
  | .ok module => module.imports.isEmpty && module.runtimeOperations.isEmpty &&
      (Fir.Wasm.validateModule module).isOk && (Fir.Wasm.Emit.encode module).isOk
  | .error _ => false

end Fir.Wasm.Emit.ResidentNatArithmetic
