import Fir.Wasm.Emit.ResidentCallSite
import Fir.Wasm.Emit.ResidentNumeric

namespace Fir.Wasm.Emit.ResidentBigNumeric

open Fir.Wasm
open Fir.Wasm.Concrete
open Lean
open Lean.Compiler

/-!
# Wasm-resident arbitrary-precision `prettyM` Nat/Int frontier

This layer leaves the generation-ready one-limb helpers in `ResidentNumeric`
unchanged and installs a versioned helper set over the same W6 layouts. Calls
from compiler-generated functions are redirected to this layer; the stable
one-limb exports remain available for W6's current proof work.

The implementation accepts canonical immediate, promoted-tag, and
arbitrary-limb Natural/Integer values. Structured loops keep the stack usage of
every limb walker independent of the represented magnitude without changing
the public helper signatures or the W6 numeric layout.
-/

inductive LinkError where
  | invalidInput (error : SymbolicError)
  | missingAllocator
  | missingNumericHelper (name : Name)
  | reservedDeclaration (name : Name)
  | incompatibleMemory
  | invalidOutput (error : SymbolicError)
  | callSite (error : ResidentCallSite.Error)
  deriving Inhabited, Repr

private def u32 (value : Nat) : UInt32 := UInt32.ofNat value

private def valueParam : FVarId := ⟨`value⟩
private def leftParam : FVarId := ⟨`left⟩
private def rightParam : FVarId := ⟨`right⟩
private def flavorParam : FVarId := ⟨`flavor⟩
private def leftFlavorParam : FVarId := ⟨`leftFlavor⟩
private def rightFlavorParam : FVarId := ⟨`rightFlavor⟩
private def indexParam : FVarId := ⟨`index⟩
private def countParam : FVarId := ⟨`count⟩
private def signParam : FVarId := ⟨`sign⟩
private def invertParam : FVarId := ⟨`invertRight⟩
private def carryParam : FVarId := ⟨`carryIn⟩
private def borrowParam : FVarId := ⟨`borrowIn⟩
private def lastParam : FVarId := ⟨`lastNonzero⟩
private def resultParam : FVarId := ⟨`resultAddress⟩
private def storeCountParam : FVarId := ⟨`storeCount⟩

private def countLocal : FVarId := ⟨`countValue⟩
private def leftCountLocal : FVarId := ⟨`leftCount⟩
private def rightCountLocal : FVarId := ⟨`rightCount⟩
private def resultCountLocal : FVarId := ⟨`resultCount⟩
private def scaledLocal : FVarId := ⟨`scaledValue⟩
private def addressLocal : FVarId := ⟨`address⟩
private def rawLocal : FVarId := ⟨`raw⟩
private def savedScratchLocal : FVarId := ⟨`savedScratch⟩
private def objectResultLocal : FVarId := ⟨`objectResult⟩
private def inlineAddLeftLocal : FVarId := ⟨`_fir_inline_Nat_add_left⟩
private def inlineAddRightLocal : FVarId := ⟨`_fir_inline_Nat_add_right⟩
private def inlineAddPayloadLocal : FVarId := ⟨`_fir_inline_Nat_add_payload⟩
private def inlineAddResultLocal : FVarId := ⟨`_fir_inline_Nat_add_result⟩
private def inlineSubLeftLocal : FVarId := ⟨`_fir_inline_Nat_sub_left⟩
private def inlineSubRightLocal : FVarId := ⟨`_fir_inline_Nat_sub_right⟩
private def inlineSubResultLocal : FVarId := ⟨`_fir_inline_Nat_sub_result⟩
private def inlineDecisionLeftLocal : FVarId :=
  ⟨`_fir_inline_Nat_decision_left⟩
private def inlineDecisionRightLocal : FVarId :=
  ⟨`_fir_inline_Nat_decision_right⟩
private def inlineDecisionResultLocal : FVarId :=
  ⟨`_fir_inline_Nat_decision_result⟩
private def decisionResultLocal : FVarId := ⟨`decisionResult⟩
private def leftLowLocal : FVarId := ⟨`leftLowValue⟩
private def leftHighLocal : FVarId := ⟨`leftHighValue⟩
private def rightLowLocal : FVarId := ⟨`rightLowValue⟩
private def rightHighLocal : FVarId := ⟨`rightHighValue⟩
private def lowLocal : FVarId := ⟨`lowValue⟩
private def highLocal : FVarId := ⟨`highValue⟩
private def carryLocal : FVarId := ⟨`carryValue⟩
private def borrowLocal : FVarId := ⟨`borrowValue⟩
private def carryExtraLocal : FVarId := ⟨`carryExtra⟩
private def borrowExtraLocal : FVarId := ⟨`borrowExtra⟩
private def compareLocal : FVarId := ⟨`compareValue⟩
private def nextIndexLocal : FVarId := ⟨`nextIndex⟩
private def nextLastLocal : FVarId := ⟨`nextLast⟩
private def leftSignLocal : FVarId := ⟨`leftSign⟩
private def rightSignLocal : FVarId := ⟨`rightSign⟩
private def resultSignLocal : FVarId := ⟨`resultSign⟩
private def minuendLocal : FVarId := ⟨`minuend⟩
private def subtrahendLocal : FVarId := ⟨`subtrahend⟩
private def naturalLocal : FVarId := ⟨`naturalValue⟩
private def integerLocal : FVarId := ⟨`integerValue⟩

private def compareAtLoop : FVarId := ⟨`compareAtLoop⟩
private def copyFromLoop : FVarId := ⟨`copyFromLoop⟩
private def sumCarryFromLoop : FVarId := ⟨`sumCarryFromLoop⟩
private def writeSumFromLoop : FVarId := ⟨`writeSumFromLoop⟩
private def differenceScanFromLoop : FVarId := ⟨`differenceScanFromLoop⟩
private def writeDifferenceFromLoop : FVarId := ⟨`writeDifferenceFromLoop⟩

def validateCommonName : Name := `fir_big_numeric_validate_common
def validateNaturalName : Name := `fir_big_numeric_validate_natural
def validateIntegerName : Name := `fir_big_numeric_validate_integer
def naturalCountName : Name := `fir_big_numeric_natural_count
def naturalLowName : Name := `fir_big_numeric_natural_low
def naturalHighName : Name := `fir_big_numeric_natural_high
def integerCountName : Name := `fir_big_numeric_integer_count
def integerSignName : Name := `fir_big_numeric_integer_sign
def integerLowName : Name := `fir_big_numeric_integer_low
def integerHighName : Name := `fir_big_numeric_integer_high
def magnitudeCountName : Name := `fir_big_numeric_magnitude_count
def magnitudeLowName : Name := `fir_big_numeric_magnitude_low
def magnitudeHighName : Name := `fir_big_numeric_magnitude_high
def allocateName : Name := `fir_big_numeric_allocate
def compareAtName : Name := `fir_big_numeric_compare_at
def compareName : Name := `fir_big_numeric_compare
def copyFromName : Name := `fir_big_numeric_copy_from
def sumCarryFromName : Name := `fir_big_numeric_sum_carry_from
def writeSumFromName : Name := `fir_big_numeric_write_sum_from
def differenceScanFromName : Name := `fir_big_numeric_difference_scan_from
def writeDifferenceFromName : Name := `fir_big_numeric_write_difference_from
def differenceLowName : Name := `fir_big_numeric_difference_low
def differenceHighName : Name := `fir_big_numeric_difference_high
def integerCombineName : Name := `fir_big_numeric_integer_combine

def externalName (declaration : Name) : Name :=
  Name.mkSimple s!"fir_big_ext_{declaration.toString.replace "." "_"}"

def externalHelperNames : Array Name :=
  ResidentNumeric.externalDeclarations.map externalName

private def equalsConst (kind : AbiKind) (value : UInt32) :
    List Instruction :=
  [.i32Const kind value, .i32Eq]

private def trapWhenTrue (condition : List Instruction) : List Instruction :=
  condition ++ [.ifElse [.unreachable] []]

private def trapUnlessTrue (condition : List Instruction) : List Instruction :=
  trapWhenTrue (condition ++ equalsConst .uint32 0)

private def load32 (object : FVarId) (offset : Nat) :
    List Instruction :=
  [.localGet object, .i32Load .uint32 (u32 offset)]

private def requireHeapAddress (object : FVarId) : List Instruction :=
  trapWhenTrue [
    .localGet object,
    .i32Const .uint32 (u32 heapBase),
    .i32LtU] ++
  trapWhenTrue [
    .localGet object,
    .i32Const .uint32 (u32 (target.heapAlignment - 1)),
    .i32And]

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

private def limbAddress (object index scaled : FVarId) :
    List Instruction :=
  scale8 index scaled ++ [
    .localGet object,
    .i32Const .uint32 (u32 headerBytes),
    .i32Add,
    .localGet scaled,
    .i32Add]

private def dynamicLimbLoad (object index scaled : FVarId) (offset : Nat) :
    List Instruction :=
  limbAddress object index scaled ++ [.i32Load .uint32 (u32 offset)]

private def dynamicLimbStore (object index scaled value : FVarId)
    (offset : Nat) : List Instruction :=
  limbAddress object index scaled ++ [
    .localGet value,
    .i32Store .uint32 (u32 offset)]

private def countFitsExtent : List Instruction := [
  .localGet countLocal,
  .i32Const .uint32 536870908,
  .i32LtU]

private def expectedExtent : List Instruction :=
  scale8 countLocal scaledLocal ++ [
    .i32Const .uint32 (u32 headerBytes),
    .localGet scaledLocal,
    .i32Add]

def validateCommonFunction : Function := {
  name := validateCommonName
  params := #[(valueParam, .tobject)]
  results := #[.uint32]
  locals := #[
    (countLocal, .uint32),
    (scaledLocal, .uint32)]
  body :=
    requireHeapAddress valueParam ++
    trapUnlessTrue (
      load32 valueParam headerFlagsOffset ++
      [.i32Const .uint32 liveFlag, .i32And]) ++
    [
      .localGet valueParam,
      .i32Load .uint32 (u32 headerAux1Offset),
      .localSet countLocal] ++
    trapUnlessTrue [
      .localGet countLocal] ++
    trapUnlessTrue countFitsExtent ++
    trapUnlessTrue (
      load32 valueParam headerAllocationBytesOffset ++
      expectedExtent ++ [.i32Eq]) ++
    [
      .localGet countLocal,
      .ret] }

private def requirePersistent : List Instruction :=
  trapUnlessTrue (
    load32 valueParam headerFlagsOffset ++
    [.i32Const .uint32 persistentFlag, .i32And]) ++
  trapWhenTrue (load32 valueParam headerRefCountOffset)

private def requireOrdinaryOrPersistent : List Instruction :=
  load32 valueParam headerFlagsOffset ++
  equalsConst .uint32 (liveFlag + persistentFlag) ++
  [.ifElse
    (trapWhenTrue (load32 valueParam headerRefCountOffset))
    (trapUnlessTrue (
        load32 valueParam headerFlagsOffset ++
        equalsConst .uint32 liveFlag) ++
      trapUnlessTrue (load32 valueParam headerRefCountOffset))]

private def requireReservedZero : List Instruction :=
  trapWhenTrue (load32 valueParam headerAux2Offset) ++
  trapWhenTrue (load32 valueParam headerAux3Offset)

private def requireOneCount : List Instruction :=
  trapUnlessTrue [
    .localGet countLocal,
    .i32Const .uint32 1,
    .i32Eq]

private def loadTopLow : List Instruction := [
  .localGet valueParam,
  .localGet countLocal,
  .i32Const .uint32 1,
  .i32Sub,
  .call (.declaration naturalLowName)]

private def loadTopHigh : List Instruction := [
  .localGet valueParam,
  .localGet countLocal,
  .i32Const .uint32 1,
  .i32Sub,
  .call (.declaration naturalHighName)]

private def requireTopNonzero : List Instruction :=
  trapUnlessTrue (
    (loadTopLow ++ equalsConst .uint32 0) ++
    (loadTopHigh ++ equalsConst .uint32 0) ++
    [.i32And] ++
    equalsConst .uint32 0)

private def naturalPromotedValidation : List Instruction :=
  requireOneCount ++ requirePersistent ++ requireReservedZero ++
  trapUnlessTrue (
    loadTopHigh ++
    [.i32Const .uint32 2147483648, .i32LtU]) ++
  loadTopHigh ++ equalsConst .uint32 0 ++
  [.ifElse
    (trapUnlessTrue (
      [.i32Const .uint32 (u32 maxImmediatePayload)] ++
      loadTopLow ++
      [.i32LtU]))
    []]

private def naturalBigValidation : List Instruction :=
  requireOrdinaryOrPersistent ++ requireReservedZero ++ requireTopNonzero ++
  [.localGet countLocal,
    .i32Const .uint32 1,
    .i32Eq,
    .ifElse
      (trapWhenTrue (
        loadTopHigh ++
        [.i32Const .uint32 2147483648, .i32LtU]))
      []]

def validateNaturalFunction : Function := {
  name := validateNaturalName
  params := #[(valueParam, .tobject)]
  results := #[]
  locals := #[(countLocal, .uint32)]
  body := [
    .localGet valueParam,
    .i32Const .uint32 1,
    .i32And,
    .ifElse
      [.ret]
      ([
        .localGet valueParam,
        .call (.declaration validateCommonName),
        .localSet countLocal] ++
        trapUnlessTrue (
          load32 valueParam headerKindOffset ++
          equalsConst .uint32 ObjectKind.natural.code) ++
        load32 valueParam headerAux0Offset ++
        equalsConst .uint32 promotedTagMarker ++
        [.ifElse
          (naturalPromotedValidation ++ [.ret])
          (trapUnlessTrue (
              load32 valueParam headerAux0Offset ++
              equalsConst .uint32 bigNaturalMarker) ++
            naturalBigValidation ++
            [.ret])])] }

private def integerPromotedValidation : List Instruction :=
  requireOneCount ++ requirePersistent ++ requireReservedZero ++
  trapWhenTrue loadTopHigh ++
  trapWhenTrue (
    loadTopLow ++
    [.i32Const .uint32 2147483648, .i32LtU])

private def requireCanonicalIntegerOneLimb : List Instruction := [
  .localGet countLocal,
  .i32Const .uint32 1,
  .i32Eq,
  .ifElse
    (loadTopHigh ++ equalsConst .uint32 0 ++
      [.ifElse
        (load32 valueParam headerAux2Offset ++
          [.ifElse
            (trapUnlessTrue (
              [.i32Const .uint32 2147483648] ++
              loadTopLow ++
              [.i32LtU]))
            (trapWhenTrue (
              loadTopLow ++
              [.i32Const .uint32 2147483648, .i32LtU]))])
        []])
    []]

private def integerHeapValidation : List Instruction :=
  requireOrdinaryOrPersistent ++
  trapUnlessTrue (
    load32 valueParam headerAux0Offset ++
    equalsConst .uint32 integerSignMagnitudeMarker) ++
  trapUnlessTrue (
    load32 valueParam headerAux2Offset ++
    [.i32Const .uint32 2, .i32LtU]) ++
  trapWhenTrue (load32 valueParam headerAux3Offset) ++
  requireTopNonzero ++
  requireCanonicalIntegerOneLimb

def validateIntegerFunction : Function := {
  name := validateIntegerName
  params := #[(valueParam, .tobject)]
  results := #[]
  locals := #[(countLocal, .uint32)]
  body := [
    .localGet valueParam,
    .i32Const .uint32 1,
    .i32And,
    .ifElse
      [.ret]
      ([
        .localGet valueParam,
        .call (.declaration validateCommonName),
        .localSet countLocal] ++
        load32 valueParam headerKindOffset ++
        equalsConst .uint32 ObjectKind.natural.code ++
        [.ifElse
          (trapUnlessTrue (
              load32 valueParam headerAux0Offset ++
              equalsConst .uint32 promotedTagMarker) ++
            integerPromotedValidation ++
            [.ret])
          (trapUnlessTrue (
              load32 valueParam headerKindOffset ++
              equalsConst .uint32 ObjectKind.integer.code) ++
            integerHeapValidation ++
            [.ret])])] }

def naturalCountFunction : Function := {
  name := naturalCountName
  params := #[(valueParam, .tobject)]
  results := #[.uint32]
  locals := #[]
  body := [
    .localGet valueParam,
    .i32Const .uint32 1,
    .i32And,
    .ifElse
      [.i32Const .uint32 1, .ret]
      (load32 valueParam headerAux1Offset ++ [.ret])] }

private def naturalLimbFunction (name : Name) (offset : Nat) : Function := {
  name
  params := #[(valueParam, .tobject), (indexParam, .uint32)]
  results := #[.uint32]
  locals := #[(scaledLocal, .uint32)]
  body := [
    .localGet valueParam,
    .i32Const .uint32 1,
    .i32And,
    .ifElse
      ([.localGet indexParam,
        .i32Const .uint32 0,
        .i32Eq,
        .ifElse
          (if offset == 0 then
            [.localGet valueParam,
              .i32Const .uint32 1,
              .i32ShrU,
              .ret]
           else
            [.i32Const .uint32 0, .ret])
          [.i32Const .uint32 0, .ret]])
      (dynamicLimbLoad valueParam indexParam scaledLocal offset ++ [.ret])] }

def naturalLowFunction : Function := naturalLimbFunction naturalLowName 0
def naturalHighFunction : Function := naturalLimbFunction naturalHighName 4

def integerCountFunction : Function := {
  name := integerCountName
  params := #[(valueParam, .tobject)]
  results := #[.uint32]
  locals := #[]
  body := [
    .localGet valueParam,
    .i32Const .uint32 1,
    .i32And,
    .ifElse
      [.i32Const .uint32 1, .ret]
      (load32 valueParam headerKindOffset ++
        equalsConst .uint32 ObjectKind.natural.code ++
        [.ifElse
          [.i32Const .uint32 1, .ret]
          (load32 valueParam headerAux1Offset ++ [.ret])])] }

def integerSignFunction : Function := {
  name := integerSignName
  params := #[(valueParam, .tobject)]
  results := #[.uint32]
  locals := #[]
  body := [
    .localGet valueParam,
    .i32Const .uint32 1,
    .i32And,
    .ifElse
      [.i32Const .uint32 0, .ret]
      (load32 valueParam headerKindOffset ++
        equalsConst .uint32 ObjectKind.natural.code ++
        [.ifElse
          [.i32Const .uint32 1, .ret]
          (load32 valueParam headerAux2Offset ++ [.ret])])] }

private def integerLimbFunction (name : Name) (offset : Nat) : Function := {
  name
  params := #[(valueParam, .tobject), (indexParam, .uint32)]
  results := #[.uint32]
  locals := #[(scaledLocal, .uint32)]
  body := [
    .localGet valueParam,
    .i32Const .uint32 1,
    .i32And,
    .ifElse
      ([.localGet indexParam,
        .i32Const .uint32 0,
        .i32Eq,
        .ifElse
          (if offset == 0 then
            [.localGet valueParam,
              .i32Const .uint32 1,
              .i32ShrU,
              .ret]
           else
            [.i32Const .uint32 0, .ret])
          [.i32Const .uint32 0, .ret]])
      (load32 valueParam headerKindOffset ++
        equalsConst .uint32 ObjectKind.natural.code ++
        [.ifElse
          ([.localGet indexParam,
            .i32Const .uint32 0,
            .i32Eq,
            .ifElse
              (if offset == 0 then
                [.i32Const .uint32 0] ++
                dynamicLimbLoad valueParam indexParam scaledLocal 0 ++
                [.i32Sub, .ret]
               else
                [.i32Const .uint32 0, .ret])
              [.i32Const .uint32 0, .ret]])
          (dynamicLimbLoad valueParam indexParam scaledLocal offset ++ [.ret])])] }

def integerLowFunction : Function := integerLimbFunction integerLowName 0
def integerHighFunction : Function := integerLimbFunction integerHighName 4

def magnitudeCountFunction : Function := {
  name := magnitudeCountName
  params := #[(valueParam, .tobject), (flavorParam, .uint32)]
  results := #[.uint32]
  locals := #[]
  body := [
    .localGet flavorParam,
    .ifElse
      [.localGet valueParam, .call (.declaration integerCountName), .ret]
      [.localGet valueParam, .call (.declaration naturalCountName), .ret]] }

private def magnitudeLimbFunction (name natural integer : Name) : Function := {
  name
  params := #[
    (valueParam, .tobject),
    (flavorParam, .uint32),
    (indexParam, .uint32)]
  results := #[.uint32]
  locals := #[(countLocal, .uint32)]
  body := [
    .localGet valueParam,
    .localGet flavorParam,
    .call (.declaration magnitudeCountName),
    .localSet countLocal,
    .localGet indexParam,
    .localGet countLocal,
    .i32LtU,
    .ifElse
      [.localGet flavorParam,
        .ifElse
          [.localGet valueParam,
            .localGet indexParam,
            .call (.declaration integer),
            .ret]
          [.localGet valueParam,
            .localGet indexParam,
            .call (.declaration natural),
            .ret]]
      [.i32Const .uint32 0, .ret]] }

def magnitudeLowFunction : Function :=
  magnitudeLimbFunction magnitudeLowName naturalLowName integerLowName

def magnitudeHighFunction : Function :=
  magnitudeLimbFunction magnitudeHighName naturalHighName integerHighName

def validationAndAccessFunctions : Array Function := #[
  validateCommonFunction,
  naturalCountFunction,
  naturalLowFunction,
  naturalHighFunction,
  validateNaturalFunction,
  integerCountFunction,
  integerSignFunction,
  integerLowFunction,
  integerHighFunction,
  validateIntegerFunction,
  magnitudeCountFunction,
  magnitudeLowFunction,
  magnitudeHighFunction]

private def kindParam : FVarId := ⟨`kind⟩
private def markerParam : FVarId := ⟨`marker⟩

def allocateFunction : Function := {
  name := allocateName
  params := #[
    (kindParam, .uint32),
    (markerParam, .uint32),
    (signParam, .uint32),
    (countParam, .uint32)]
  results := #[.uint32]
  locals := #[
    (scaledLocal, .uint32),
    (addressLocal, .uint32)]
  body :=
    trapUnlessTrue [
      .localGet countParam,
      .i32Const .uint32 536870908,
      .i32LtU] ++
    scale8 countParam scaledLocal ++ [
      .i32Const .uint32 (u32 headerBytes),
      .localGet scaledLocal,
      .i32Add,
      .call (.declaration ResidentAllocator.allocateName),
      .localSet addressLocal,
      .localGet addressLocal,
      .localGet kindParam,
      .i32Store .uint32 (u32 headerKindOffset),
      .localGet addressLocal,
      .i32Const .uint32 liveFlag,
      .i32Store .uint32 (u32 headerFlagsOffset),
      .localGet addressLocal,
      .i32Const .uint32 1,
      .i32Store .uint32 (u32 headerRefCountOffset),
      .localGet addressLocal,
      .i32Const .uint32 (u32 headerBytes),
      .localGet scaledLocal,
      .i32Add,
      .i32Store .uint32 (u32 headerAllocationBytesOffset),
      .localGet addressLocal,
      .localGet markerParam,
      .i32Store .uint32 (u32 headerAux0Offset),
      .localGet addressLocal,
      .localGet countParam,
      .i32Store .uint32 (u32 headerAux1Offset),
      .localGet addressLocal,
      .localGet signParam,
      .i32Store .uint32 (u32 headerAux2Offset),
      .localGet addressLocal,
      .i32Const .uint32 0,
      .i32Store .uint32 (u32 headerAux3Offset),
      .localGet addressLocal,
      .ret] }

private def loadMagnitude (object flavor index low high : FVarId) :
    List Instruction := [
  .localGet object,
  .localGet flavor,
  .localGet index,
  .call (.declaration magnitudeLowName),
  .localSet low,
  .localGet object,
  .localGet flavor,
  .localGet index,
  .call (.declaration magnitudeHighName),
  .localSet high]

def compareAtFunction : Function := {
  name := compareAtName
  params := #[
    (leftParam, .tobject),
    (leftFlavorParam, .uint32),
    (rightParam, .tobject),
    (rightFlavorParam, .uint32),
    (indexParam, .uint32)]
  results := #[.uint32]
  locals := #[
    (leftLowLocal, .uint32),
    (leftHighLocal, .uint32),
    (rightLowLocal, .uint32),
    (rightHighLocal, .uint32)]
  body := [
    .loop compareAtLoop <|
      loadMagnitude leftParam leftFlavorParam indexParam
          leftLowLocal leftHighLocal ++
      loadMagnitude rightParam rightFlavorParam indexParam
          rightLowLocal rightHighLocal ++ [
        .localGet leftHighLocal,
        .localGet rightHighLocal,
        .i32Eq,
        .ifElse
          [.localGet leftLowLocal,
            .localGet rightLowLocal,
            .i32Eq,
            .ifElse
              [.localGet indexParam,
                .i32Const .uint32 0,
                .i32Eq,
                .ifElse
                  [.i32Const .uint32 0, .ret]
                  [.localGet indexParam,
                    .i32Const .uint32 1,
                    .i32Sub,
                    .localSet indexParam,
                    .br compareAtLoop]]
              [.localGet leftLowLocal,
                .localGet rightLowLocal,
                .i32LtU,
                .ifElse
                  [.i32Const .uint32 1, .ret]
                  [.i32Const .uint32 2, .ret]]]
          [.localGet leftHighLocal,
            .localGet rightHighLocal,
            .i32LtU,
            .ifElse
              [.i32Const .uint32 1, .ret]
              [.i32Const .uint32 2, .ret]]]] }

def compareFunction : Function := {
  name := compareName
  params := #[
    (leftParam, .tobject),
    (leftFlavorParam, .uint32),
    (rightParam, .tobject),
    (rightFlavorParam, .uint32)]
  results := #[.uint32]
  locals := #[
    (leftCountLocal, .uint32),
    (rightCountLocal, .uint32)]
  body := [
    .localGet leftParam,
    .localGet leftFlavorParam,
    .call (.declaration magnitudeCountName),
    .localSet leftCountLocal,
    .localGet rightParam,
    .localGet rightFlavorParam,
    .call (.declaration magnitudeCountName),
    .localSet rightCountLocal,
    .localGet leftCountLocal,
    .localGet rightCountLocal,
    .i32Eq,
    .ifElse
      [.localGet leftParam,
        .localGet leftFlavorParam,
        .localGet rightParam,
        .localGet rightFlavorParam,
        .localGet leftCountLocal,
        .i32Const .uint32 1,
        .i32Sub,
        .call (.declaration compareAtName),
        .ret]
      [.localGet leftCountLocal,
        .localGet rightCountLocal,
        .i32LtU,
        .ifElse
          [.i32Const .uint32 1, .ret]
          [.i32Const .uint32 2, .ret]]] }

def copyFromFunction : Function := {
  name := copyFromName
  params := #[
    (valueParam, .tobject),
    (flavorParam, .uint32),
    (resultParam, .uint32),
    (indexParam, .uint32),
    (countParam, .uint32)]
  results := #[]
  locals := #[
    (lowLocal, .uint32),
    (highLocal, .uint32),
    (scaledLocal, .uint32)]
  body := [
    .loop copyFromLoop <| [
      .localGet indexParam,
      .localGet countParam,
      .i32Eq,
      .ifElse [.ret] []] ++
      loadMagnitude valueParam flavorParam indexParam lowLocal highLocal ++
      dynamicLimbStore resultParam indexParam scaledLocal lowLocal 0 ++
      dynamicLimbStore resultParam indexParam scaledLocal highLocal 4 ++ [
        .localGet indexParam,
        .i32Const .uint32 1,
        .i32Add,
        .localSet indexParam,
        .br copyFromLoop]] }

private def sumStep : List Instruction :=
  loadMagnitude leftParam leftFlavorParam indexParam
      leftLowLocal leftHighLocal ++
  loadMagnitude rightParam rightFlavorParam indexParam
      rightLowLocal rightHighLocal ++ [
    .localGet leftLowLocal,
    .localGet rightLowLocal,
    .i32Add,
    .localSet lowLocal,
    .localGet lowLocal,
    .localGet leftLowLocal,
    .i32LtU,
    .localSet carryLocal,
    .localGet lowLocal,
    .localGet carryParam,
    .i32Add,
    .localSet lowLocal,
    .localGet lowLocal,
    .localGet carryParam,
    .i32LtU,
    .localSet carryExtraLocal,
    .localGet carryLocal,
    .localGet carryExtraLocal,
    .i32Add,
    .localSet carryLocal,
    .localGet leftHighLocal,
    .localGet rightHighLocal,
    .i32Add,
    .localSet highLocal,
    .localGet highLocal,
    .localGet leftHighLocal,
    .i32LtU,
    .localSet carryExtraLocal,
    .localGet highLocal,
    .localGet carryLocal,
    .i32Add,
    .localSet highLocal,
    .localGet highLocal,
    .localGet carryLocal,
    .i32LtU,
    .localSet carryLocal,
    .localGet carryLocal,
    .localGet carryExtraLocal,
    .i32Add,
    .localSet carryLocal]

private def arithmeticLocals : Array (FVarId × AbiKind) := #[
  (leftLowLocal, .uint32),
  (leftHighLocal, .uint32),
  (rightLowLocal, .uint32),
  (rightHighLocal, .uint32),
  (lowLocal, .uint32),
  (highLocal, .uint32),
  (carryLocal, .uint32),
  (carryExtraLocal, .uint32),
  (scaledLocal, .uint32)]

def sumCarryFromFunction : Function := {
  name := sumCarryFromName
  params := #[
    (leftParam, .tobject),
    (leftFlavorParam, .uint32),
    (rightParam, .tobject),
    (rightFlavorParam, .uint32),
    (indexParam, .uint32),
    (countParam, .uint32),
    (carryParam, .uint32)]
  results := #[.uint32]
  locals := arithmeticLocals
  body := [
    .loop sumCarryFromLoop <| [
      .localGet indexParam,
      .localGet countParam,
      .i32Eq,
      .ifElse [.localGet carryParam, .ret] []] ++
      sumStep ++ [
        .localGet carryLocal,
        .localSet carryParam,
        .localGet indexParam,
        .i32Const .uint32 1,
        .i32Add,
        .localSet indexParam,
        .br sumCarryFromLoop]] }

def writeSumFromFunction : Function := {
  name := writeSumFromName
  params := #[
    (leftParam, .tobject),
    (leftFlavorParam, .uint32),
    (rightParam, .tobject),
    (rightFlavorParam, .uint32),
    (resultParam, .uint32),
    (indexParam, .uint32),
    (countParam, .uint32),
    (carryParam, .uint32)]
  results := #[.uint32]
  locals := arithmeticLocals
  body := [
    .loop writeSumFromLoop <| [
      .localGet indexParam,
      .localGet countParam,
      .i32Eq,
      .ifElse [.localGet carryParam, .ret] []] ++
      sumStep ++
      dynamicLimbStore resultParam indexParam scaledLocal lowLocal 0 ++
      dynamicLimbStore resultParam indexParam scaledLocal highLocal 4 ++ [
        .localGet carryLocal,
        .localSet carryParam,
        .localGet indexParam,
        .i32Const .uint32 1,
        .i32Add,
        .localSet indexParam,
        .br writeSumFromLoop]] }

private def differenceStep : List Instruction :=
  loadMagnitude leftParam leftFlavorParam indexParam
      leftLowLocal leftHighLocal ++
  loadMagnitude rightParam rightFlavorParam indexParam
      rightLowLocal rightHighLocal ++ [
    .localGet leftLowLocal,
    .localGet rightLowLocal,
    .i32Sub,
    .localSet lowLocal,
    .localGet leftLowLocal,
    .localGet rightLowLocal,
    .i32LtU,
    .localSet borrowLocal,
    .localGet lowLocal,
    .localGet borrowParam,
    .i32LtU,
    .localSet borrowExtraLocal,
    .localGet lowLocal,
    .localGet borrowParam,
    .i32Sub,
    .localSet lowLocal,
    .localGet borrowLocal,
    .localGet borrowExtraLocal,
    .i32Add,
    .localSet borrowLocal,
    .localGet leftHighLocal,
    .localGet rightHighLocal,
    .i32Sub,
    .localSet highLocal,
    .localGet leftHighLocal,
    .localGet rightHighLocal,
    .i32LtU,
    .localSet borrowExtraLocal,
    .localGet highLocal,
    .localGet borrowLocal,
    .i32LtU,
    .localSet carryExtraLocal,
    .localGet highLocal,
    .localGet borrowLocal,
    .i32Sub,
    .localSet highLocal,
    .localGet borrowExtraLocal,
    .localGet carryExtraLocal,
    .i32Add,
    .localSet borrowLocal]

private def differenceLocals : Array (FVarId × AbiKind) :=
  arithmeticLocals ++ #[
    (borrowLocal, .uint32),
    (borrowExtraLocal, .uint32),
    (nextLastLocal, .uint32)]

def differenceScanFromFunction : Function := {
  name := differenceScanFromName
  params := #[
    (leftParam, .tobject),
    (leftFlavorParam, .uint32),
    (rightParam, .tobject),
    (rightFlavorParam, .uint32),
    (indexParam, .uint32),
    (countParam, .uint32),
    (borrowParam, .uint32),
    (lastParam, .uint32)]
  results := #[.uint32]
  locals := differenceLocals
  body := [
    .loop differenceScanFromLoop <| [
      .localGet indexParam,
      .localGet countParam,
      .i32Eq,
      .ifElse
        (trapWhenTrue [.localGet borrowParam] ++
          [.localGet lastParam, .ret])
        []] ++
      differenceStep ++ [
        .localGet lowLocal,
        .i32Const .uint32 0,
        .i32Eq,
        .localGet highLocal,
        .i32Const .uint32 0,
        .i32Eq,
        .i32And,
        .ifElse
          [.localGet lastParam, .localSet nextLastLocal]
          [.localGet indexParam,
            .i32Const .uint32 1,
            .i32Add,
            .localSet nextLastLocal],
        .localGet nextLastLocal,
        .localSet lastParam,
        .localGet borrowLocal,
        .localSet borrowParam,
        .localGet indexParam,
        .i32Const .uint32 1,
        .i32Add,
        .localSet indexParam,
        .br differenceScanFromLoop]] }

def writeDifferenceFromFunction : Function := {
  name := writeDifferenceFromName
  params := #[
    (leftParam, .tobject),
    (leftFlavorParam, .uint32),
    (rightParam, .tobject),
    (rightFlavorParam, .uint32),
    (resultParam, .uint32),
    (indexParam, .uint32),
    (countParam, .uint32),
    (storeCountParam, .uint32),
    (borrowParam, .uint32)]
  results := #[]
  locals := differenceLocals
  body := [
    .loop writeDifferenceFromLoop <| [
      .localGet indexParam,
      .localGet countParam,
      .i32Eq,
      .ifElse (trapWhenTrue [.localGet borrowParam] ++ [.ret]) []] ++
      differenceStep ++ [
        .localGet indexParam,
        .localGet storeCountParam,
        .i32LtU,
        .ifElse
          (dynamicLimbStore resultParam indexParam scaledLocal lowLocal 0 ++
            dynamicLimbStore resultParam indexParam scaledLocal highLocal 4)
          [],
        .localGet borrowLocal,
        .localSet borrowParam,
        .localGet indexParam,
        .i32Const .uint32 1,
        .i32Add,
        .localSet indexParam,
        .br writeDifferenceFromLoop]] }

def differenceLowFunction : Function := {
  name := differenceLowName
  params := #[
    (leftParam, .tobject),
    (leftFlavorParam, .uint32),
    (rightParam, .tobject),
    (rightFlavorParam, .uint32)]
  results := #[.uint32]
  locals := #[
    (leftLowLocal, .uint32),
    (rightLowLocal, .uint32)]
  body := [
    .localGet leftParam,
    .localGet leftFlavorParam,
    .i32Const .uint32 0,
    .call (.declaration magnitudeLowName),
    .localSet leftLowLocal,
    .localGet rightParam,
    .localGet rightFlavorParam,
    .i32Const .uint32 0,
    .call (.declaration magnitudeLowName),
    .localSet rightLowLocal,
    .localGet leftLowLocal,
    .localGet rightLowLocal,
    .i32Sub,
    .ret] }

def differenceHighFunction : Function := {
  name := differenceHighName
  params := #[
    (leftParam, .tobject),
    (leftFlavorParam, .uint32),
    (rightParam, .tobject),
    (rightFlavorParam, .uint32)]
  results := #[.uint32]
  locals := #[
    (leftLowLocal, .uint32),
    (leftHighLocal, .uint32),
    (rightLowLocal, .uint32),
    (rightHighLocal, .uint32),
    (borrowLocal, .uint32)]
  body := [
      .localGet leftParam,
      .localGet leftFlavorParam,
      .i32Const .uint32 0,
      .call (.declaration magnitudeLowName),
      .localSet leftLowLocal,
      .localGet leftParam,
      .localGet leftFlavorParam,
      .i32Const .uint32 0,
      .call (.declaration magnitudeHighName),
      .localSet leftHighLocal,
      .localGet rightParam,
      .localGet rightFlavorParam,
      .i32Const .uint32 0,
      .call (.declaration magnitudeLowName),
      .localSet rightLowLocal,
      .localGet rightParam,
      .localGet rightFlavorParam,
      .i32Const .uint32 0,
      .call (.declaration magnitudeHighName),
      .localSet rightHighLocal,
      .localGet leftLowLocal,
      .localGet rightLowLocal,
      .i32LtU,
      .localSet borrowLocal,
      .localGet leftHighLocal,
      .localGet rightHighLocal,
      .i32Sub,
      .localGet borrowLocal,
      .i32Sub,
      .ret] }

def limbFunctions : Array Function := #[
  allocateFunction,
  compareAtFunction,
  compareFunction,
  copyFromFunction,
  sumCarryFromFunction,
  writeSumFromFunction,
  differenceScanFromFunction,
  writeDifferenceFromFunction,
  differenceLowFunction,
  differenceHighFunction]

private def retypeRawResult (result : AbiKind) (resultLocal : FVarId) :
    List Instruction := [
  .localSet rawLocal,
  .i32Const .uint32 0,
  .i32Load .uint32 0,
  .localSet savedScratchLocal,
  .i32Const .uint32 0,
  .localGet rawLocal,
  .i32Store .uint32 0,
  .i32Const .uint32 0,
  .i32Load result 0,
  .localSet resultLocal,
  .i32Const .uint32 0,
  .localGet savedScratchLocal,
  .i32Store .uint32 0,
  .localGet resultLocal,
  .ret]

private def objectResultLocals : Array (FVarId × AbiKind) := #[
  (rawLocal, .uint32),
  (savedScratchLocal, .uint32),
  (objectResultLocal, .tobject)]

private def decisionResultLocals : Array (FVarId × AbiKind) := #[
  (rawLocal, .uint32),
  (savedScratchLocal, .uint32),
  (decisionResultLocal, .uint8)]

/-- Retype a physical decision bit without borrowing linear-memory scratch.

The symbolic ABI distinguishes a raw `UInt32` comparison result from the
`UInt8` result expected by Lean's decision procedures.  The zero extension and
wrap preserve every bit of the already-normalized `0`/`1` result while moving
it through instructions whose result kinds make that distinction explicit.
The final Wasm optimizer can erase this physical no-op pair. -/
private def retypeDecisionResult : List Instruction := [
  .i64ExtendI32U .uint64,
  .i32WrapI64 .uint8,
  .ret]

#guard retypeDecisionResult == [
  .i64ExtendI32U .uint64,
  .i32WrapI64 .uint8,
  .ret]

/-- Retype a physical word already known to be a valid Lean object result
without borrowing linear-memory scratch.

This helper is deliberately narrower than `retypeRawResult`: callers must
establish that the input word is already a valid tagged immediate or live heap
object.  Extending to `UInt64` and wrapping back to `tobject` preserves all 32
bits while making the symbolic ABI-kind transition explicit.  The final Wasm
optimizer can erase this physical no-op pair. -/
private def retypeKnownObjectResult : List Instruction := [
  .i64ExtendI32U .uint64,
  .i32WrapI64 .tobject,
  .ret]

#guard retypeKnownObjectResult == [
  .i64ExtendI32U .uint64,
  .i32WrapI64 .tobject,
  .ret]

private def loadCount (object flavor destination : FVarId) :
    List Instruction := [
  .localGet object,
  .localGet flavor,
  .call (.declaration magnitudeCountName),
  .localSet destination]

private def loadFirstMagnitude (object flavor low high : FVarId) :
    List Instruction := [
  .localGet object,
  .localGet flavor,
  .i32Const .uint32 0,
  .call (.declaration magnitudeLowName),
  .localSet low,
  .localGet object,
  .localGet flavor,
  .i32Const .uint32 0,
  .call (.declaration magnitudeHighName),
  .localSet high]

private def allocateNatural (count : FVarId) : List Instruction := [
  .i32Const .uint32 ObjectKind.natural.code,
  .i32Const .uint32 bigNaturalMarker,
  .i32Const .uint32 0,
  .localGet count,
  .call (.declaration allocateName)]

private def allocateInteger (sign count : FVarId) : List Instruction := [
  .i32Const .uint32 ObjectKind.integer.code,
  .i32Const .uint32 integerSignMagnitudeMarker,
  .localGet sign,
  .localGet count,
  .call (.declaration allocateName)]

private def allocateIntegerConst (sign : UInt32) (count : FVarId) :
    List Instruction := [
  .i32Const .uint32 ObjectKind.integer.code,
  .i32Const .uint32 integerSignMagnitudeMarker,
  .i32Const .uint32 sign,
  .localGet count,
  .call (.declaration allocateName)]

private def storeConstantLimbPart (object index scaled : FVarId)
    (value : UInt32) (offset : Nat) : List Instruction :=
  limbAddress object index scaled ++ [
    .i32Const .uint32 value,
    .i32Store .uint32 (u32 offset)]

private def copyInto (source flavor result count : FVarId) :
    List Instruction := [
  .localGet source,
  .localGet flavor,
  .localGet result,
  .i32Const .uint32 0,
  .localGet count,
  .call (.declaration copyFromName)]

private def maxCounts : List Instruction := [
  .localGet leftCountLocal,
  .localGet rightCountLocal,
  .i32LtU,
  .ifElse
    [.localGet rightCountLocal, .localSet countLocal]
    [.localGet leftCountLocal, .localSet countLocal]]

private def callSumCarry : List Instruction := [
  .localGet leftParam,
  .localGet leftFlavorParam,
  .localGet rightParam,
  .localGet rightFlavorParam,
  .i32Const .uint32 0,
  .localGet countLocal,
  .i32Const .uint32 0,
  .call (.declaration sumCarryFromName),
  .localSet carryLocal,
  .localGet countLocal,
  .localGet carryLocal,
  .i32Add,
  .localSet resultCountLocal]

private def writeSum (result : FVarId) : List Instruction := [
  .localGet leftParam,
  .localGet leftFlavorParam,
  .localGet rightParam,
  .localGet rightFlavorParam,
  .localGet result,
  .i32Const .uint32 0,
  .localGet countLocal,
  .i32Const .uint32 0,
  .call (.declaration writeSumFromName),
  .localSet carryExtraLocal] ++
  trapUnlessTrue [
    .localGet carryExtraLocal,
    .localGet carryLocal,
    .i32Eq] ++ [
  .localGet carryLocal,
  .ifElse
    (storeConstantLimbPart result countLocal scaledLocal 1 0 ++
      storeConstantLimbPart result countLocal scaledLocal 0 4)
    []]

private def callOneLimbNaturalSum : List Instruction :=
  loadFirstMagnitude leftParam leftFlavorParam leftLowLocal leftHighLocal ++
  loadFirstMagnitude rightParam rightFlavorParam rightLowLocal rightHighLocal ++ [
    .localGet leftLowLocal,
    .localGet leftHighLocal,
    .localGet rightLowLocal,
    .localGet rightHighLocal,
    .call (.declaration ResidentNumeric.naturalSumName)]

private def callOneLimbIntegerSum (sign : FVarId) : List Instruction :=
  loadFirstMagnitude leftParam leftFlavorParam leftLowLocal leftHighLocal ++
  loadFirstMagnitude rightParam rightFlavorParam rightLowLocal rightHighLocal ++ [
    .localGet sign,
    .localGet leftLowLocal,
    .localGet leftHighLocal,
    .localGet rightLowLocal,
    .localGet rightHighLocal,
    .call (.declaration ResidentNumeric.integerSumName)]

private def callDifferencePart (name : Name) (left leftFlavor right rightFlavor :
    FVarId) : List Instruction := [
  .localGet left,
  .localGet leftFlavor,
  .localGet right,
  .localGet rightFlavor,
  .call (.declaration name)]

def intOfNatFunction : Function := {
  name := externalName `Int.ofNat
  params := #[(valueParam, .tobject)]
  results := #[.tobject]
  locals := objectResultLocals ++ #[
    (flavorParam, .uint32),
    (countLocal, .uint32),
    (lowLocal, .uint32),
    (highLocal, .uint32)]
  body := [
    .i32Const .uint32 0,
    .localSet flavorParam,
    .localGet valueParam,
    .call (.declaration validateNaturalName)] ++
    loadCount valueParam flavorParam countLocal ++ [
    .localGet countLocal,
    .i32Const .uint32 1,
    .i32Eq,
    .ifElse
      (loadFirstMagnitude valueParam flavorParam lowLocal highLocal ++ [
        .i32Const .uint32 0,
        .localGet lowLocal,
        .localGet highLocal,
        .call (.declaration ResidentNumeric.makeIntegerName)] ++
        retypeRawResult .tobject objectResultLocal)
      (allocateIntegerConst 0 countLocal ++ [
        .localSet rawLocal] ++
        copyInto valueParam flavorParam rawLocal countLocal ++ [
        .localGet rawLocal] ++
        retypeRawResult .tobject objectResultLocal)] }

def intNatAbsFunction : Function := {
  name := externalName `Int.natAbs
  params := #[(valueParam, .tobject)]
  results := #[.tobject]
  locals := objectResultLocals ++ #[
    (flavorParam, .uint32),
    (countLocal, .uint32),
    (lowLocal, .uint32),
    (highLocal, .uint32)]
  body := [
    .i32Const .uint32 1,
    .localSet flavorParam,
    .localGet valueParam,
    .call (.declaration validateIntegerName)] ++
    loadCount valueParam flavorParam countLocal ++ [
    .localGet countLocal,
    .i32Const .uint32 1,
    .i32Eq,
    .ifElse
      (loadFirstMagnitude valueParam flavorParam lowLocal highLocal ++ [
        .localGet lowLocal,
        .localGet highLocal,
        .call (.declaration ResidentNumeric.makeNaturalName)] ++
        retypeRawResult .tobject objectResultLocal)
      (allocateNatural countLocal ++ [
        .localSet rawLocal] ++
        copyInto valueParam flavorParam rawLocal countLocal ++ [
        .localGet rawLocal] ++
        retypeRawResult .tobject objectResultLocal)] }

private def naturalArithmeticLocals : Array (FVarId × AbiKind) :=
  objectResultLocals ++ #[
    (leftFlavorParam, .uint32),
    (rightFlavorParam, .uint32),
    (leftCountLocal, .uint32),
    (rightCountLocal, .uint32),
    (countLocal, .uint32),
    (resultCountLocal, .uint32),
    (leftLowLocal, .uint32),
    (leftHighLocal, .uint32),
    (rightLowLocal, .uint32),
    (rightHighLocal, .uint32),
    (carryLocal, .uint32),
    (carryExtraLocal, .uint32),
    (scaledLocal, .uint32),
    (compareLocal, .uint32)]

private def validateNaturalsAndCounts : List Instruction := [
  .localGet leftParam,
  .call (.declaration validateNaturalName),
  .localGet rightParam,
  .call (.declaration validateNaturalName)] ++
  loadCount leftParam leftFlavorParam leftCountLocal ++
  loadCount rightParam rightFlavorParam rightCountLocal

/-- Both operands use the wasm32 immediate representation.  This is a
representation check, not a semantic relaxation: every odd object word is a
canonical nonnegative Nat payload in the concrete ABI. -/
def bothImmediateNaturals (left right : FVarId) : List Instruction := [
  .localGet left,
  .i32Const .uint32 1,
  .i32And,
  .localGet right,
  .i32Const .uint32 1,
  .i32And,
  .i32And]

/-- Decode the 31-bit payload of a Nat already selected by
`bothImmediateNaturals`. -/
def immediateNaturalPayload (value : FVarId) : List Instruction := [
  .localGet value,
  .i32Const .uint32 1,
  .i32ShrU]

/-- Reusable binary Nat representation dispatch.  The immediate body may
assume both operands are canonical tagged immediates; every other
representation reaches the checked arbitrary-precision fallback. -/
def withImmediateNaturalPair (left right : FVarId)
    (immediate fallback : List Instruction) : List Instruction :=
  bothImmediateNaturals left right ++ [.ifElse immediate fallback]

private def boxImmediatePayload (payload : FVarId) : List Instruction := [
  .localGet payload,
  .i64ExtendI32U .uint64,
  .i64Const .uint64 1,
  .i64Shl,
  .i64Const .uint64 1,
  .i64Or,
  .i32WrapI64 .tagged]

private def natAddCallSiteBody (fallback : Name) : List Instruction := [
  .localSet inlineAddRightLocal,
  .localSet inlineAddLeftLocal,
  .localGet inlineAddLeftLocal,
  .i32Const .uint32 1,
  .i32And,
  .localGet inlineAddRightLocal,
  .i32Const .uint32 1,
  .i32And,
  .i32And,
  .ifElse
    (immediateNaturalPayload inlineAddLeftLocal ++
      immediateNaturalPayload inlineAddRightLocal ++ [
        .i32Add,
        .localSet inlineAddPayloadLocal,
        .localGet inlineAddPayloadLocal,
        .i32Const .uint32 2147483648,
        .i32LtU,
        .ifElse
          (boxImmediatePayload inlineAddPayloadLocal ++ [
            .localSet inlineAddResultLocal])
          [.localGet inlineAddLeftLocal,
            .localGet inlineAddRightLocal,
            .call (.declaration fallback),
            .localSet inlineAddResultLocal]])
    [.localGet inlineAddLeftLocal,
      .localGet inlineAddRightLocal,
      .call (.declaration fallback),
      .localSet inlineAddResultLocal],
  .localGet inlineAddResultLocal]

private def natAddCallSiteRewriteFor (target fallback : Name) :
    ResidentCallSite.Rewrite := {
  target := .declaration target
  signature := { params := #[.tobject, .tobject], results := #[.tobject] }
  locals := #[(inlineAddLeftLocal, .tobject),
    (inlineAddRightLocal, .tobject), (inlineAddPayloadLocal, .uint32),
    (inlineAddResultLocal, .tobject)]
  body := natAddCallSiteBody fallback }

private def natSubCallSiteBody (fallback : Name) : List Instruction := [
  .localSet inlineSubRightLocal,
  .localSet inlineSubLeftLocal,
  .localGet inlineSubLeftLocal,
  .i32Const .uint32 1,
  .i32And,
  .localGet inlineSubRightLocal,
  .i32Const .uint32 1,
  .i32And,
  .i32And,
  .ifElse [
    .localGet inlineSubLeftLocal,
    .localGet inlineSubRightLocal,
    .i32LtU,
    .ifElse
      [.i32Const .tobject 1,
        .localSet inlineSubResultLocal]
      [.localGet inlineSubLeftLocal,
        .localGet inlineSubRightLocal,
        .i32Sub,
        .i32Const .uint32 1,
        .i32Add,
        .i64ExtendI32U .uint64,
        .i32WrapI64 .tagged,
        .localSet inlineSubResultLocal]
  ] [
    .localGet inlineSubLeftLocal,
    .localGet inlineSubRightLocal,
    .call (.declaration fallback),
    .localSet inlineSubResultLocal],
  .localGet inlineSubResultLocal]

private def natSubCallSiteRewriteFor (target fallback : Name) :
    ResidentCallSite.Rewrite := {
  target := .declaration target
  signature := { params := #[.tobject, .tobject], results := #[.tobject] }
  locals := #[(inlineSubLeftLocal, .tobject),
    (inlineSubRightLocal, .tobject), (inlineSubResultLocal, .tobject)]
  /- `Nat.sub left right ≤ left`. A tagged left operand therefore bounds the
  result by the complete immediate payload range, independently of the right
  representation. Preserve that fact on the caller-local result so later
  ownership lowering can erase its checked release. -/
  conditionalResultRefinement? := some {
    argumentKinds := #[some .tagged, none]
    kind := .tagged }
  body := natSubCallSiteBody fallback }

private def natDecisionCallSiteBody (fallback : Name)
    (comparison : Instruction) : List Instruction := [
  .localSet inlineDecisionRightLocal,
  .localSet inlineDecisionLeftLocal,
  .localGet inlineDecisionLeftLocal,
  .i32Const .uint32 1,
  .i32And,
  .localGet inlineDecisionRightLocal,
  .i32Const .uint32 1,
  .i32And,
  .i32And,
  .ifElse
    [.localGet inlineDecisionLeftLocal,
      .localGet inlineDecisionRightLocal,
      comparison,
      .i64ExtendI32U .uint64,
      .i32WrapI64 .uint8,
      .localSet inlineDecisionResultLocal]
    [.localGet inlineDecisionLeftLocal,
      .localGet inlineDecisionRightLocal,
      .call (.declaration fallback),
      .localSet inlineDecisionResultLocal],
  .localGet inlineDecisionResultLocal]

private def natDecisionCallSiteRewriteFor (target fallback : Name)
    (comparison : Instruction) :
    ResidentCallSite.Rewrite := {
  target := .declaration target
  signature := { params := #[.tobject, .tobject], results := #[.uint8] }
  locals := #[(inlineDecisionLeftLocal, .tobject),
    (inlineDecisionRightLocal, .tobject),
    (inlineDecisionResultLocal, .uint8)]
  body := natDecisionCallSiteBody fallback comparison }

/-- Mirror upstream's always-inline Nat arithmetic and decision wrappers at
original typed callers. Sums which no longer fit the wasm32 tagged payload,
and decisions over any non-immediate pair, retain the complete resident
helper. Canonical tagged Nat words preserve equality and unsigned order. -/
def callSiteRewrites : Array ResidentCallSite.Rewrite := #[
  natAddCallSiteRewriteFor `Nat.add (externalName `Nat.add),
  natSubCallSiteRewriteFor `Nat.sub (externalName `Nat.sub),
  natDecisionCallSiteRewriteFor `Nat.decEq (externalName `Nat.decEq) .i32Eq,
  natDecisionCallSiteRewriteFor `Nat.decLt (externalName `Nat.decLt) .i32LtU,
  natDecisionCallSiteRewriteFor `Nat.decLe (externalName `Nat.decLe) .i32LeU]

private def internalCallSiteRewrites : Array ResidentCallSite.Rewrite := #[
  natAddCallSiteRewriteFor (ResidentNumeric.externalName `Nat.add)
    (externalName `Nat.add),
  natSubCallSiteRewriteFor (ResidentNumeric.externalName `Nat.sub)
    (externalName `Nat.sub),
  natDecisionCallSiteRewriteFor (ResidentNumeric.externalName `Nat.decEq)
    (externalName `Nat.decEq) .i32Eq,
  natDecisionCallSiteRewriteFor (ResidentNumeric.externalName `Nat.decLt)
    (externalName `Nat.decLt) .i32LtU,
  natDecisionCallSiteRewriteFor (ResidentNumeric.externalName `Nat.decLe)
    (externalName `Nat.decLe) .i32LeU]

private partial def callSiteContains (needle : Instruction) :
    Instruction → Bool
  | .block _ body | .loop _ body => body.any (callSiteContains needle)
  | .ifElse thenBody elseBody =>
      thenBody.any (callSiteContains needle) ||
        elseBody.any (callSiteContains needle)
  | instruction => instruction == needle

#guard callSiteRewrites[0]!.locals.size == 4
#guard callSiteRewrites[0]!.body.any
  (callSiteContains (.i32Const .uint32 2147483648))
#guard callSiteRewrites[1]!.body.any (callSiteContains .i32Sub)
#guard callSiteRewrites.size == 5
#guard callSiteRewrites[2]!.signature.results == #[.uint8]
#guard callSiteRewrites[2]!.body.any (callSiteContains .i32Eq)
#guard callSiteRewrites[3]!.body.any (callSiteContains .i32LtU)
#guard callSiteRewrites[4]!.body.any (callSiteContains .i32LeU)

/-- Decode two immediate Nat payloads and reuse the existing bounded natural
sum constructor.  That constructor returns an immediate when the sum fits and
the canonical promoted representation when it crosses the wasm32 immediate
boundary. -/
private def callImmediateNaturalSum : List Instruction :=
  immediateNaturalPayload leftParam ++ [.i32Const .uint32 0] ++
  immediateNaturalPayload rightParam ++ [
    .i32Const .uint32 0,
    .call (.declaration ResidentNumeric.naturalSumName)]

private partial def instructionUsesObjectScratchRetype : Instruction → Bool
  | .i32Load .tobject 0 => true
  | .block _ body | .loop _ body =>
      body.any instructionUsesObjectScratchRetype
  | .ifElse thenBody elseBody =>
      thenBody.any instructionUsesObjectScratchRetype ||
        elseBody.any instructionUsesObjectScratchRetype
  | _ => false

def natAddFunction : Function := {
  name := externalName `Nat.add
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.tobject]
  locals := naturalArithmeticLocals
  body := withImmediateNaturalPair leftParam rightParam
    (callImmediateNaturalSum ++
      retypeKnownObjectResult)
    ([.i32Const .uint32 0,
        .localSet leftFlavorParam,
        .i32Const .uint32 0,
        .localSet rightFlavorParam] ++
        validateNaturalsAndCounts ++ maxCounts ++ callSumCarry ++ [
        .localGet resultCountLocal,
        .i32Const .uint32 1,
        .i32Eq,
        .ifElse
          (callOneLimbNaturalSum ++
            retypeKnownObjectResult)
          (allocateNatural resultCountLocal ++ [
            .localSet rawLocal] ++
            writeSum rawLocal ++ [
            .localGet rawLocal] ++
            retypeKnownObjectResult)]) }

/- `Nat.add` validates every checked operand before constructing its result,
so all three exits already hold either a canonical tagged Nat or a live
resident Natural.  No exit should reborrow linear-memory address zero merely
to change the symbolic result kind. -/
#guard !natAddFunction.body.any instructionUsesObjectScratchRetype

private def scanDifference (left leftFlavor right rightFlavor total : FVarId) :
    List Instruction := [
  .localGet left,
  .localGet leftFlavor,
  .localGet right,
  .localGet rightFlavor,
  .i32Const .uint32 0,
  .localGet total,
  .i32Const .uint32 0,
  .i32Const .uint32 0,
  .call (.declaration differenceScanFromName),
  .localSet resultCountLocal]

private def writeDifference (left leftFlavor right rightFlavor result total store :
    FVarId) : List Instruction := [
  .localGet left,
  .localGet leftFlavor,
  .localGet right,
  .localGet rightFlavor,
  .localGet result,
  .i32Const .uint32 0,
  .localGet total,
  .localGet store,
  .i32Const .uint32 0,
  .call (.declaration writeDifferenceFromName)]

private def finishNaturalDifference : List Instruction :=
  scanDifference leftParam leftFlavorParam rightParam rightFlavorParam leftCountLocal ++ [
    .localGet resultCountLocal,
    .i32Const .uint32 1,
    .i32Eq,
    .ifElse
      (callDifferencePart differenceLowName leftParam leftFlavorParam
          rightParam rightFlavorParam ++
        callDifferencePart differenceHighName leftParam leftFlavorParam
          rightParam rightFlavorParam ++
        [.call (.declaration ResidentNumeric.makeNaturalName)] ++
        retypeRawResult .tobject objectResultLocal)
      (allocateNatural resultCountLocal ++ [
        .localSet rawLocal] ++
        writeDifference leftParam leftFlavorParam rightParam rightFlavorParam
          rawLocal leftCountLocal resultCountLocal ++ [
        .localGet rawLocal] ++
        retypeRawResult .tobject objectResultLocal)]

/-- Tagged Nat words preserve unsigned payload order.  Subtracting the two
words cancels their tag bits; adding the tag back therefore computes the
canonical immediate word for truncated natural subtraction without decoding
or allocating. -/
private def immediateNaturalDifference : List Instruction := [
  .localGet leftParam,
  .localGet rightParam,
  .i32LtU,
  .ifElse
    [.i32Const .uint32 1,
      .localSet rawLocal]
    [.localGet leftParam,
      .localGet rightParam,
      .i32Sub,
      .i32Const .uint32 1,
      .i32Add,
      .localSet rawLocal],
  .localGet rawLocal] ++
  retypeRawResult .tobject objectResultLocal

private def checkedNaturalDifference : List Instruction := [
  .i32Const .uint32 0,
  .localSet leftFlavorParam,
  .i32Const .uint32 0,
  .localSet rightFlavorParam] ++
  validateNaturalsAndCounts ++ [
  .localGet leftParam,
  .i32Const .uint32 0,
  .localGet rightParam,
  .i32Const .uint32 0,
  .call (.declaration compareName),
  .localSet compareLocal,
  .localGet compareLocal,
  .i32Const .uint32 2,
  .i32Eq,
  .ifElse
    finishNaturalDifference
    ([.i32Const .uint32 0,
      .i32Const .uint32 0,
      .call (.declaration ResidentNumeric.makeNaturalName)] ++
      retypeRawResult .tobject objectResultLocal)]

def natSubFunction : Function := {
  name := externalName `Nat.sub
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.tobject]
  locals := naturalArithmeticLocals
  body := withImmediateNaturalPair leftParam rightParam
    immediateNaturalDifference checkedNaturalDifference }

private def integerCombineLocals : Array (FVarId × AbiKind) := #[
  (leftFlavorParam, .uint32),
  (rightFlavorParam, .uint32),
  (leftCountLocal, .uint32),
  (rightCountLocal, .uint32),
  (countLocal, .uint32),
  (resultCountLocal, .uint32),
  (leftLowLocal, .uint32),
  (leftHighLocal, .uint32),
  (rightLowLocal, .uint32),
  (rightHighLocal, .uint32),
  (leftSignLocal, .uint32),
  (rightSignLocal, .uint32),
  (resultSignLocal, .uint32),
  (carryLocal, .uint32),
  (carryExtraLocal, .uint32),
  (scaledLocal, .uint32),
  (compareLocal, .uint32),
  (rawLocal, .uint32),
  (minuendLocal, .tobject),
  (subtrahendLocal, .tobject)]

private def finishIntegerSum : List Instruction :=
  maxCounts ++ callSumCarry ++ [
    .localGet resultCountLocal,
    .i32Const .uint32 1,
    .i32Eq,
    .ifElse
      (callOneLimbIntegerSum resultSignLocal ++ [.ret])
      (allocateInteger resultSignLocal resultCountLocal ++ [
        .localSet rawLocal] ++
        writeSum rawLocal ++ [
        .localGet rawLocal,
        .ret])]

private def finishIntegerDifference : List Instruction :=
  scanDifference minuendLocal leftFlavorParam subtrahendLocal
      rightFlavorParam countLocal ++ [
    .localGet resultCountLocal,
    .i32Const .uint32 1,
    .i32Eq,
    .ifElse
      ([.localGet resultSignLocal] ++
        callDifferencePart differenceLowName minuendLocal leftFlavorParam
          subtrahendLocal rightFlavorParam ++
        callDifferencePart differenceHighName minuendLocal leftFlavorParam
          subtrahendLocal rightFlavorParam ++
        [.call (.declaration ResidentNumeric.makeIntegerName),
          .ret])
      (allocateInteger resultSignLocal resultCountLocal ++ [
        .localSet rawLocal] ++
        writeDifference minuendLocal leftFlavorParam subtrahendLocal
          rightFlavorParam rawLocal countLocal resultCountLocal ++ [
        .localGet rawLocal,
        .ret])]

private def finishIntegerOppositeSigns : List Instruction := [
  .localGet leftParam,
  .i32Const .uint32 1,
  .localGet rightParam,
  .i32Const .uint32 1,
  .call (.declaration compareName),
  .localSet compareLocal,
  .localGet compareLocal,
  .i32Const .uint32 0,
  .i32Eq,
  .ifElse
    [.i32Const .uint32 0,
      .i32Const .uint32 0,
      .i32Const .uint32 0,
      .call (.declaration ResidentNumeric.makeIntegerName),
      .ret]
    ([.localGet compareLocal,
      .i32Const .uint32 1,
      .i32Eq,
      .ifElse
        [.localGet rightParam,
          .localSet minuendLocal,
          .localGet leftParam,
          .localSet subtrahendLocal,
          .localGet rightSignLocal,
          .localSet resultSignLocal,
          .localGet rightCountLocal,
          .localSet countLocal]
        [.localGet leftParam,
          .localSet minuendLocal,
          .localGet rightParam,
          .localSet subtrahendLocal,
          .localGet leftSignLocal,
          .localSet resultSignLocal,
          .localGet leftCountLocal,
          .localSet countLocal]] ++
      finishIntegerDifference)]

def integerCombineFunction : Function := {
  name := integerCombineName
  params := #[
    (leftParam, .tobject),
    (rightParam, .tobject),
    (invertParam, .uint32)]
  results := #[.uint32]
  locals := integerCombineLocals
  body := [
    .i32Const .uint32 1,
    .localSet leftFlavorParam,
    .i32Const .uint32 1,
    .localSet rightFlavorParam,
    .localGet leftParam,
    .call (.declaration validateIntegerName),
    .localGet rightParam,
    .call (.declaration validateIntegerName),
    .localGet leftParam,
    .call (.declaration integerCountName),
    .localSet leftCountLocal,
    .localGet rightParam,
    .call (.declaration integerCountName),
    .localSet rightCountLocal,
    .localGet leftParam,
    .call (.declaration integerSignName),
    .localSet leftSignLocal,
    .localGet rightParam,
    .call (.declaration integerSignName),
    .localSet rightSignLocal,
    .localGet invertParam,
    .ifElse
      [.i32Const .uint32 1,
        .localGet rightSignLocal,
        .i32Sub,
        .localSet rightSignLocal]
      [],
    .localGet leftSignLocal,
    .localGet rightSignLocal,
    .i32Eq,
    .ifElse
      ([.localGet leftSignLocal,
        .localSet resultSignLocal] ++
        finishIntegerSum)
      finishIntegerOppositeSigns] }

def intAddFunction : Function := {
  name := externalName `Int.add
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.tobject]
  locals := objectResultLocals
  body := [
    .localGet leftParam,
    .localGet rightParam,
    .i32Const .uint32 0,
    .call (.declaration integerCombineName)] ++
    retypeRawResult .tobject objectResultLocal }

def intSubFunction : Function := {
  name := externalName `Int.sub
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.tobject]
  locals := objectResultLocals
  body := [
    .localGet leftParam,
    .localGet rightParam,
    .i32Const .uint32 1,
    .call (.declaration integerCombineName)] ++
    retypeRawResult .tobject objectResultLocal }

def intNegFunction : Function := {
  name := externalName `Int.neg
  params := #[(valueParam, .tobject)]
  results := #[.tobject]
  locals := objectResultLocals
  body := [
    .i32Const .tobject 1,
    .localGet valueParam,
    .i32Const .uint32 1,
    .call (.declaration integerCombineName)] ++
    retypeRawResult .tobject objectResultLocal }

def intNegSuccFunction : Function := {
  name := externalName `Int.negSucc
  params := #[(valueParam, .tobject)]
  results := #[.tobject]
  locals := objectResultLocals ++ #[(naturalLocal, .tobject), (integerLocal, .tobject)]
  body := [
    .localGet valueParam,
    .i32Const .tobject 3,
    .call (.declaration (externalName `Nat.add)),
    .localSet naturalLocal,
    .localGet naturalLocal,
    .call (.declaration (externalName `Int.ofNat)),
    .localSet integerLocal,
    .i32Const .tobject 1,
    .localGet integerLocal,
    .i32Const .uint32 1,
    .call (.declaration integerCombineName)] ++
    retypeRawResult .tobject objectResultLocal }

inductive DecisionKind where
  | eq
  | lt
  | le

private def immediateNaturalDecision (kind : DecisionKind) : List Instruction :=
  [.localGet leftParam, .localGet rightParam] ++
  match kind with
  | .eq => [.i32Eq]
  | .lt => [.i32LtU]
  | .le => [.i32LeU]

private def checkedNaturalDecision (kind : DecisionKind) : List Instruction := [
  .localGet leftParam,
  .call (.declaration validateNaturalName),
  .localGet rightParam,
  .call (.declaration validateNaturalName),
  .localGet leftParam,
  .i32Const .uint32 0,
  .localGet rightParam,
  .i32Const .uint32 0,
  .call (.declaration compareName),
  .localSet compareLocal] ++
  (match kind with
  | .eq =>
      [.localGet compareLocal,
        .i32Const .uint32 0,
        .i32Eq]
  | .lt =>
      [.localGet compareLocal,
        .i32Const .uint32 1,
        .i32Eq]
  | .le =>
      [.localGet compareLocal,
        .i32Const .uint32 2,
        .i32LtU])

private def naturalDecisionBody (kind : DecisionKind) : List Instruction :=
  withImmediateNaturalPair leftParam rightParam
    (immediateNaturalDecision kind ++ [.localSet rawLocal])
    (checkedNaturalDecision kind ++ [.localSet rawLocal]) ++ [
    .localGet rawLocal] ++
  retypeDecisionResult

private def naturalDecisionLocals : Array (FVarId × AbiKind) :=
  #[(rawLocal, .uint32), (compareLocal, .uint32)]

def natDecEqFunction : Function := {
  name := externalName `Nat.decEq
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.uint8]
  locals := naturalDecisionLocals
  body := naturalDecisionBody .eq }

def natDecLtFunction : Function := {
  name := externalName `Nat.decLt
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.uint8]
  locals := naturalDecisionLocals
  body := naturalDecisionBody .lt }

def natDecLeFunction : Function := {
  name := externalName `Nat.decLe
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.uint8]
  locals := naturalDecisionLocals
  body := naturalDecisionBody .le }

def intDecLtFunction : Function := {
  name := externalName `Int.decLt
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.uint8]
  locals := decisionResultLocals ++ #[
    (leftSignLocal, .uint32),
    (rightSignLocal, .uint32),
    (compareLocal, .uint32)]
  body := [
    .localGet leftParam,
    .call (.declaration validateIntegerName),
    .localGet rightParam,
    .call (.declaration validateIntegerName),
    .localGet leftParam,
    .call (.declaration integerSignName),
    .localSet leftSignLocal,
    .localGet rightParam,
    .call (.declaration integerSignName),
    .localSet rightSignLocal,
    .localGet leftSignLocal,
    .localGet rightSignLocal,
    .i32Eq,
    .ifElse
      [.localGet leftParam,
        .i32Const .uint32 1,
        .localGet rightParam,
        .i32Const .uint32 1,
        .call (.declaration compareName),
        .localSet compareLocal,
        .localGet leftSignLocal,
        .ifElse
          [.localGet compareLocal,
            .i32Const .uint32 2,
            .i32Eq,
            .localSet rawLocal]
          [.localGet compareLocal,
            .i32Const .uint32 1,
            .i32Eq,
            .localSet rawLocal]]
      [.localGet leftSignLocal,
        .localSet rawLocal],
    .localGet rawLocal] ++
    retypeRawResult .uint8 decisionResultLocal }

def intDecEqFunction : Function := {
  name := externalName `Int.decEq
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.uint8]
  locals := decisionResultLocals ++ #[(leftSignLocal, .uint32),
    (rightSignLocal, .uint32), (compareLocal, .uint32)]
  body := [
    .localGet leftParam,
    .call (.declaration validateIntegerName),
    .localGet rightParam,
    .call (.declaration validateIntegerName),
    .localGet leftParam,
    .call (.declaration integerSignName),
    .localSet leftSignLocal,
    .localGet rightParam,
    .call (.declaration integerSignName),
    .localSet rightSignLocal,
    .localGet leftParam,
    .i32Const .uint32 1,
    .localGet rightParam,
    .i32Const .uint32 1,
    .call (.declaration compareName),
    .localSet compareLocal,
    .localGet leftSignLocal,
    .localGet rightSignLocal,
    .i32Eq,
    .localGet compareLocal,
    .i32Eqz,
    .i32And] ++
    retypeRawResult .uint8 decisionResultLocal }

def intDecLeFunction : Function := {
  name := externalName `Int.decLe
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[.uint8]
  locals := decisionResultLocals ++ #[
    (leftSignLocal, .uint32),
    (rightSignLocal, .uint32),
    (compareLocal, .uint32)]
  body := [
    .localGet leftParam,
    .call (.declaration validateIntegerName),
    .localGet rightParam,
    .call (.declaration validateIntegerName),
    .localGet leftParam,
    .call (.declaration integerSignName),
    .localSet leftSignLocal,
    .localGet rightParam,
    .call (.declaration integerSignName),
    .localSet rightSignLocal,
    .localGet leftSignLocal,
    .localGet rightSignLocal,
    .i32Eq,
    .ifElse
      [.localGet leftParam,
        .i32Const .uint32 1,
        .localGet rightParam,
        .i32Const .uint32 1,
        .call (.declaration compareName),
        .localSet compareLocal,
        .localGet leftSignLocal,
        .ifElse
          [.localGet compareLocal,
            .i32Const .uint32 1,
            .i32Eq,
            .i32Eqz,
            .localSet rawLocal]
          [.localGet compareLocal,
            .i32Const .uint32 2,
            .i32LtU,
            .localSet rawLocal]]
      [.localGet leftSignLocal,
        .localSet rawLocal],
    .localGet rawLocal] ++
    retypeRawResult .uint8 decisionResultLocal }

def externalFunctions : Array Function := #[
  intOfNatFunction,
  intNegSuccFunction,
  intNegFunction,
  intDecEqFunction,
  intDecLtFunction,
  intDecLeFunction,
  intNatAbsFunction,
  intSubFunction,
  natAddFunction,
  natDecEqFunction,
  natSubFunction,
  intAddFunction,
  natDecLtFunction,
  natDecLeFunction]

def internalFunctions : Array Function :=
  validationAndAccessFunctions ++ limbFunctions ++ #[integerCombineFunction]

def internalHelperNames : Array Name := #[
  validateCommonName,
  validateNaturalName,
  validateIntegerName,
  naturalCountName,
  naturalLowName,
  naturalHighName,
  integerCountName,
  integerSignName,
  integerLowName,
  integerHighName,
  magnitudeCountName,
  magnitudeLowName,
  magnitudeHighName,
  allocateName,
  compareAtName,
  compareName,
  copyFromName,
  sumCarryFromName,
  writeSumFromName,
  differenceScanFromName,
  writeDifferenceFromName,
  differenceLowName,
  differenceHighName,
  integerCombineName]

def helperNames : Array Name := internalHelperNames ++ externalHelperNames

private def replacementNames : Std.HashMap Name Name :=
  ResidentNumeric.externalDeclarations.foldl
    (init := Std.HashMap.emptyWithCapacity ResidentNumeric.externalDeclarations.size)
    fun names declaration =>
      names.insert (ResidentNumeric.externalName declaration) (externalName declaration)

private partial def rewriteInstruction
    (replacements : Std.HashMap Name Name) : Instruction → Instruction
  | .call (.declaration name) =>
      match replacements.get? name with
      | some replacement => .call (.declaration replacement)
      | none => .call (.declaration name)
  | .block label body =>
      .block label (body.map (rewriteInstruction replacements))
  | .loop label body =>
      .loop label (body.map (rewriteInstruction replacements))
  | .ifElse thenBody elseBody =>
      .ifElse
        (thenBody.map (rewriteInstruction replacements))
        (elseBody.map (rewriteInstruction replacements))
  | instruction => instruction

private def rewriteFunction (function : Function) : Function :=
  { function with body := function.body.map (rewriteInstruction replacementNames) }

def internalize (module : Module) (validate : Bool := true) : Except LinkError Module := do
  if validate then
    match Fir.Wasm.validateModule module with
    | .ok () => pure ()
    | .error error => throw (.invalidInput error)
  unless module.functions.any (·.name == ResidentAllocator.allocateName) do
    throw .missingAllocator
  unless module.memory == some ResidentRuntime.residentMemory do
    throw .incompatibleMemory
  for name in ResidentNumeric.helperNames do
    unless module.functions.any (·.name == name) do
      throw (.missingNumericHelper name)
  for name in helperNames do
    if module.imports.any (·.declaration? == some name) ||
        module.functions.any (·.name == name) ||
        module.exports.contains name then
      throw (.reservedDeclaration name)
  let callerRewritten ←
    ResidentCallSite.rewriteModuleFunctions internalCallSiteRewrites module
      |>.mapError LinkError.callSite
  let result : Module := {
    module with
    functions :=
      callerRewritten.map rewriteFunction ++ internalFunctions ++ externalFunctions
    exports := helperNames.foldl Fir.Wasm.addUnique module.exports }
  if validate then
    match Fir.Wasm.validateModule result with
    | .ok () => return result
    | .error error => throw (.invalidOutput error)
  else return result

private def natAddCallerName : Name := `fir_example_Nat_addCaller
private def natSubCallerName : Name := `fir_example_Nat_subCaller
private def natDecEqCallerName : Name := `fir_example_Nat_decEqCaller
private def natDecLtCallerName : Name := `fir_example_Nat_decLtCaller
private def natDecLeCallerName : Name := `fir_example_Nat_decLeCaller

private def binaryCallerFunction (name declaration : Name)
    (result : AbiKind) : Function := {
  name
  params := #[(leftParam, .tobject), (rightParam, .tobject)]
  results := #[result]
  locals := #[]
  body := [
    .localGet leftParam,
    .localGet rightParam,
    .call (.declaration declaration),
    .ret] }

private def natAddCallerFunction : Function :=
  binaryCallerFunction natAddCallerName
    (ResidentNumeric.externalName `Nat.add) .tobject

private def natSubCallerFunction : Function :=
  binaryCallerFunction natSubCallerName
    (ResidentNumeric.externalName `Nat.sub) .tobject

private def natDecEqCallerFunction : Function :=
  binaryCallerFunction natDecEqCallerName
    (ResidentNumeric.externalName `Nat.decEq) .uint8

private def natDecLtCallerFunction : Function :=
  binaryCallerFunction natDecLtCallerName
    (ResidentNumeric.externalName `Nat.decLt) .uint8

private def natDecLeCallerFunction : Function :=
  binaryCallerFunction natDecLeCallerName
    (ResidentNumeric.externalName `Nat.decLe) .uint8

def residentExampleModule : Except String Module := do
  let numeric ← ResidentNumeric.residentExampleModule
  let module := { numeric with
    functions := numeric.functions ++ #[natAddCallerFunction,
      natSubCallerFunction, natDecEqCallerFunction, natDecLtCallerFunction,
      natDecLeCallerFunction]
    exports := (#[natAddCallerName, natSubCallerName,
      natDecEqCallerName, natDecLtCallerName,
      natDecLeCallerName]).foldl Fir.Wasm.addUnique numeric.exports }
  internalize module
    |>.mapError fun error => s!"big numeric: {repr error}"

def manifest : Json :=
  Json.mkObj [
    ("sourceEntry", externalName `Nat.add |>.toString),
    ("entry", externalName `Nat.add |>.toString),
    ("params", Json.arr #["tobject", "tobject"]),
    ("result", "tobject"),
    ("closureDispatch", Json.arr #[]),
    ("closureDescriptors", Json.arr #[]),
    ("imports", Json.arr #[]),
    ("numericLimbBits", 64),
    ("multiLimbPolicy", "canonical-arbitrary-precision"),
    ("walkerControl", "structured-loop"),
    ("status", "generation-only; W6 arbitrary-precision contract proofs pending")]

#guard match residentExampleModule with
  | .ok module =>
      module.imports.isEmpty &&
      module.runtimeOperations.isEmpty &&
      externalHelperNames.all module.exports.contains &&
      module.memory == some ResidentRuntime.residentMemory &&
      (Fir.Wasm.validateModule module |>.isOk) &&
      (Fir.Wasm.Emit.encode module |>.isOk)
  | .error _ => false

#guard match residentExampleModule with
  | .ok module =>
      match module.functions.find? (·.name == natAddCallerName),
          module.functions.find? (·.name == natSubCallerName),
          module.functions.find? (·.name == natDecEqCallerName),
          module.functions.find? (·.name == natDecLtCallerName),
          module.functions.find? (·.name == natDecLeCallerName) with
      | some addCaller, some subCaller, some decEqCaller, some decLtCaller,
          some decLeCaller =>
          addCaller.locals.size == 4 && subCaller.locals.size == 3 &&
            decEqCaller.locals.size == 3 &&
            decLtCaller.locals.size == 3 &&
            decLeCaller.locals.size == 3 &&
            addCaller.body != natAddCallerFunction.body &&
            subCaller.body != natSubCallerFunction.body &&
            decEqCaller.body != natDecEqCallerFunction.body &&
            decLtCaller.body != natDecLtCallerFunction.body &&
            decLeCaller.body != natDecLeCallerFunction.body
      | _, _, _, _, _ => false
  | .error _ => false

end Fir.Wasm.Emit.ResidentBigNumeric
