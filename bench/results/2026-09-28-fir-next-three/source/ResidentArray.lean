import Fir.Wasm.Emit.ResidentCallSite
import Fir.Wasm.Emit.ResidentNumeric
import Fir.Wasm.Emit.ResidentReferenceCount
import Fir.Wasm.Emit.ResidentRelease
import Fir.Wasm.Emit.ResidentContainerLayout

namespace Fir.Wasm.Emit.ResidentArray

open Fir.Wasm
open Fir.Wasm.Concrete
open Lean
open Lean.Compiler

/-!
# Reference-counted resident arrays

Closed applications transfer a complete input graph and decode copied output
values. Boundary arrays may be persistent, while arrays allocated by compiled
Lean are ordinary live values with reference count one. Mutating operations
follow Lean's exclusive-update and copy-on-write discipline inside the Wasm
module; hosts only write the documented boundary layout.
-/

inductive LinkError where
  | invalidInput (error : SymbolicError)
  | missingAllocator
  | missingNumericHelper (name : Name)
  | missingOwnershipHelper (name : Name)
  | reservedDeclaration (name : Name)
  | missingExternal (name : Name)
  | incompatibleExternal (name : Name)
  | incompatibleMemory
  | invalidOutput (error : SymbolicError)
  | callSite (error : ResidentCallSite.Error)
  deriving Inhabited, Repr

private def u32 (value : Nat) : UInt32 := UInt32.ofNat value

/-- ASCII `ARRY`, stored in `opaque.aux0`. -/
def arrayMarker : UInt32 := ResidentContainerLayout.arrayMarker

def allocateEmptyName : Name := `fir_array_allocate_empty
def allocateListConsName : Name := `fir_array_allocate_list_cons
def swapElementsName : Name := `fir_array_swap_elements

def externalDeclarations : Array Name := #[
  `Array.size,
  `Array.get!InternalBorrowed,
  `Array.emptyWithCapacity,
  `Array.mkEmpty,
  `Array.getInternalBorrowed,
  `Array.push,
  `Array.get!Internal]

/--
Additional array operations linked only when the captured source closure needs
them.  They are deliberately not part of `externalDeclarations`, so the
historical strict `internalize` frontier remains source-compatible.
-/
def availableExternalDeclarations : Array Name :=
  externalDeclarations ++ #[`Array.usize, `Array.ugetBorrowed, `Array.uget,
    `Array.uset, `Array.replicate, `Array.pop, `Array.getInternal,
    `Array.set, `Array.set!, `Array.swap, `Array.mk, `Array.toList]

def externalName (declaration : Name) : Name :=
  Name.mkSimple s!"fir_ext_{declaration.toString.replace "." "_"}"

def externalHelperNames : Array Name :=
  availableExternalDeclarations.map externalName
def helperNames : Array Name :=
  #[allocateEmptyName, allocateListConsName, swapElementsName] ++ externalHelperNames

private def erasedParam : FVarId := ⟨`erased⟩
private def defaultParam : FVarId := ⟨`default⟩
private def arrayParam : FVarId := ⟨`array⟩
private def indexParam : FVarId := ⟨`index⟩
private def index2Param : FVarId := ⟨`index2⟩
private def proofParam : FVarId := ⟨`proof⟩
private def proof2Param : FVarId := ⟨`proof2⟩
private def capacityParam : FVarId := ⟨`capacity⟩
private def valueParam : FVarId := ⟨`value⟩
private def listParam : FVarId := ⟨`list⟩
private def tailParam : FVarId := ⟨`tail⟩

private def addressLocal : FVarId := ⟨`address⟩
private def inputAddressLocal : FVarId := ⟨`inputAddress⟩
private def sizeLocal : FVarId := ⟨`size⟩
private def capacityLocal : FVarId := ⟨`capacityValue⟩
private def newCapacityLocal : FVarId := ⟨`newCapacity⟩
private def refCountLocal : FVarId := ⟨`refCount⟩
private def exclusiveLocal : FVarId := ⟨`exclusive⟩
private def reuseLocal : FVarId := ⟨`reuse⟩
private def indexLocal : FVarId := ⟨`indexValue⟩
private def index2Local : FVarId := ⟨`index2Value⟩
private def indexHighLocal : FVarId := ⟨`indexHigh⟩
private def countLocal : FVarId := ⟨`count⟩
private def sourceCursorLocal : FVarId := ⟨`sourceCursor⟩
private def targetCursorLocal : FVarId := ⟨`targetCursor⟩
private def allocationBytesLocal : FVarId := ⟨`allocationBytes⟩
private def elementLocal : FVarId := ⟨`element⟩
private def element2Local : FVarId := ⟨`element2⟩
private def listLocal : FVarId := ⟨`listValue⟩
private def tailLocal : FVarId := ⟨`tailValue⟩
private def rawLocal : FVarId := ⟨`raw⟩
private def savedScratchLocal : FVarId := ⟨`savedScratch⟩
private def objectResultLocal : FVarId := ⟨`objectResult⟩
private def taggedResultLocal : FVarId := ⟨`taggedResult⟩
private def tobjectResultLocal : FVarId := ⟨`tobjectResult⟩
private def inlineSetErasedLocal : FVarId := ⟨`_fir_inline_Array_set_erased⟩
private def inlineSetArrayLocal : FVarId := ⟨`_fir_inline_Array_set_array⟩
private def inlineSetIndexParamLocal : FVarId :=
  ⟨`_fir_inline_Array_set_index_param⟩
private def inlineSetValueLocal : FVarId := ⟨`_fir_inline_Array_set_value⟩
private def inlineSetIndexLocal : FVarId := ⟨`_fir_inline_Array_set_index⟩
private def inlineSetCursorLocal : FVarId := ⟨`_fir_inline_Array_set_cursor⟩
private def inlineSetElementLocal : FVarId := ⟨`_fir_inline_Array_set_element⟩
private def inlineSetResultLocal : FVarId := ⟨`_fir_inline_Array_set_result⟩

private def copyLoopLabel : FVarId := ⟨`copyLoop⟩
private def retainedCopyLoopLabel : FVarId := ⟨`retainedCopyLoop⟩
private def listCountLoopLabel : FVarId := ⟨`arrayListCountLoop⟩
private def listFillLoopLabel : FVarId := ⟨`arrayListFillLoop⟩
private def arrayListCursorLoopLabel : FVarId := ⟨`arrayListCursorLoop⟩
private def arrayToListLoopLabel : FVarId := ⟨`arrayToListLoop⟩

private def equalsConst (kind : AbiKind) (value : UInt32) : List Instruction :=
  [.i32Const kind value, .i32Eq]

private def trapUnless (condition : List Instruction) : List Instruction :=
  condition ++ [.ifElse [] [.unreachable]]

private def trapWhenTrue (condition : List Instruction) : List Instruction :=
  condition ++ [.ifElse [.unreachable] []]

private def load32 (object : FVarId) (offset : Nat) : List Instruction :=
  [.localGet object, .i32Load .uint32 (u32 offset)]

/--
Publish one complete eight-byte FIR object lane. The wasm32 object word is
zero-extended before the physical store so allocation reuse cannot preserve a
stale high padding word from the block's previous contents.
-/
def storeObjectWord (address value : FVarId) (offset : Nat := 0) :
    List Instruction := [
  .localGet address,
  .localGet value,
  .i64ExtendI32U .uint64,
  .i64Store .uint64 (u32 offset)]

private inductive InputValidation where
  /-- Validate a raw/public Array address before inspecting its header. -/
  | checked
  /--
  Consume the resident Array invariant already carried by typed compiled
  execution. Index behavior is classified independently below.
  -/
  | trusted

private inductive ProofIndexValidation where
  /-- Reconstruct and check an erased proof premise for a raw/public call. -/
  | checked
  /-- Consume the erased proof premise carried by well-typed compiled code. -/
  | trusted

private structure CallValidation where
  input : InputValidation
  proofIndex : ProofIndexValidation

private def checkedCalls : CallValidation := {
  input := .checked
  proofIndex := .checked }

private def trustedCalls : CallValidation := {
  input := .trusted
  proofIndex := .trusted }

private def requireArray (array : FVarId) : List Instruction :=
  trapUnless ([
    .localGet array,
    .i32Const .uint32 (u32 heapBase),
    .i32LtU] ++ equalsConst .uint32 0) ++
  trapUnless (
    [.localGet array,
      .i32Const .uint32 (u32 (target.heapAlignment - 1)),
      .i32And] ++ equalsConst .uint32 0) ++
  (load32 array headerFlagsOffset ++ equalsConst .uint32 liveFlag ++
    [.ifElse
      (trapWhenTrue (load32 array headerRefCountOffset ++
        equalsConst .uint32 0))
      (trapUnless (load32 array headerFlagsOffset ++
          equalsConst .uint32 (persistentFlag + liveFlag)) ++
        trapWhenTrue (load32 array headerRefCountOffset))]) ++
  trapUnless (
    [.localGet array,
      .i32Load .uint32 (u32 headerKindOffset)] ++
      equalsConst .uint32 ObjectKind.opaque.code) ++
  trapUnless (
    [.localGet array,
      .i32Load .uint32 (u32 headerAux0Offset)] ++
      equalsConst .uint32 arrayMarker) ++
  trapWhenTrue (load32 array headerAux3Offset) ++
  trapWhenTrue (load32 array headerAux2Offset ++
    load32 array headerAux1Offset ++ [.i32LtU])

private def validateArrayInput (validation : InputValidation)
    (array : FVarId) : List Instruction :=
  match validation with
  | .checked => requireArray array
  | .trusted => []

private def listConsAllocationBytes : Nat :=
  headerBytes + 2 * target.semanticSlotBytes

/-- Validate the concrete two-object-field representation of `List.cons`. -/
private def requireListCons (list : FVarId) : List Instruction :=
  trapUnless ([
    .localGet list,
    .i32Const .uint32 (u32 heapBase),
    .i32LtU] ++ equalsConst .uint32 0) ++
  trapUnless ([
    .localGet list,
    .i32Const .uint32 (u32 (target.heapAlignment - 1)),
    .i32And] ++ equalsConst .uint32 0) ++
  (load32 list headerFlagsOffset ++ equalsConst .uint32 liveFlag ++
    [.ifElse
      (trapWhenTrue (load32 list headerRefCountOffset ++
        equalsConst .uint32 0))
      (trapUnless (load32 list headerFlagsOffset ++
          equalsConst .uint32 (persistentFlag + liveFlag)) ++
        trapWhenTrue (load32 list headerRefCountOffset))]) ++
  trapUnless (load32 list headerKindOffset ++
    equalsConst .uint32 ObjectKind.constructor.code) ++
  trapUnless (load32 list headerAllocationBytesOffset ++
    equalsConst .uint32 (u32 listConsAllocationBytes)) ++
  trapUnless (load32 list headerAux0Offset ++ equalsConst .uint32 1) ++
  trapUnless (load32 list headerAux1Offset ++ equalsConst .uint32 2) ++
  trapWhenTrue (load32 list headerAux2Offset) ++
  trapWhenTrue (load32 list headerAux3Offset)

private def loadSize (array : FVarId) : List Instruction := [
  .localGet array,
  .i32Load .uint32 (u32 headerAux1Offset),
  .localSet sizeLocal]

private def loadCapacity (array : FVarId) : List Instruction := [
  .localGet array,
  .i32Load .uint32 (u32 headerAux2Offset),
  .localSet capacityLocal]

private def decodeNaturalIndex (param destination : FVarId) : List Instruction := [
  .localGet param,
  .call (.declaration ResidentNumeric.validateNaturalName),
  .localGet param,
  .call (.declaration ResidentNumeric.naturalHighName),
  .i32Const .uint32 0,
  .i32Eq,
  .ifElse [] [.unreachable],
  .localGet param,
  .call (.declaration ResidentNumeric.naturalLowName),
  .localSet destination]

private def decodeIndex : List Instruction :=
  decodeNaturalIndex indexParam indexLocal

/-- Lean's proof-indexed Array primitives use `lean_unbox` directly. A valid
Array index is necessarily a canonical immediate Nat because the resident
wasm32 allocation bound is below the maximum immediate payload. -/
private def decodeTrustedNaturalIndex (param destination : FVarId) :
    List Instruction := [
  .localGet param,
  .i32Const .uint32 1,
  .i32ShrU,
  .localSet destination]

private def decodeProofNaturalIndex (validation : ProofIndexValidation)
    (param destination : FVarId) : List Instruction :=
  match validation with
  | .checked =>
      decodeNaturalIndex param destination ++ trapUnless [
        .localGet destination,
        .localGet sizeLocal,
        .i32LtU]
  | .trusted => decodeTrustedNaturalIndex param destination

private def decodeProofUSizeIndex (validation : ProofIndexValidation)
    (param destination : FVarId) : List Instruction :=
  match validation with
  | .checked => [
      .localGet param,
      .localGet sizeLocal,
      .i64ExtendI32U .usize,
      .i64LtU,
      .ifElse [] [.unreachable],
      .localGet param,
      .i32WrapI64 .uint32,
      .localSet destination]
  | .trusted => [
      .localGet param,
      .i32WrapI64 .uint32,
      .localSet destination]

private def storeHeaderWord (offset : Nat) (value : List Instruction) :
    List Instruction :=
  [.localGet addressLocal] ++ value ++ [.i32Store .uint32 (u32 offset)]

private def initializeHeader (newSize newCapacity : List Instruction) :
    List Instruction :=
  storeHeaderWord headerKindOffset
      [.i32Const .uint32 ObjectKind.opaque.code] ++
  storeHeaderWord headerFlagsOffset
      [.i32Const .uint32 liveFlag] ++
  storeHeaderWord headerRefCountOffset [.i32Const .uint32 1] ++
  storeHeaderWord headerAllocationBytesOffset
      [.localGet allocationBytesLocal] ++
  storeHeaderWord headerAux0Offset [.i32Const .uint32 arrayMarker] ++
  storeHeaderWord headerAux1Offset newSize ++
  storeHeaderWord headerAux2Offset newCapacity ++
  storeHeaderWord headerAux3Offset [.i32Const .uint32 0]

private def retypeAddressValue : List Instruction := [
  .i32Const .uint32 0,
  .i32Load .uint32 0,
  .localSet savedScratchLocal,
  .i32Const .uint32 0,
  .localGet addressLocal,
  .i32Store .uint32 0,
  .i32Const .uint32 0,
  .i32Load .object 0,
  .localSet objectResultLocal,
  .i32Const .uint32 0,
  .localGet savedScratchLocal,
  .i32Store .uint32 0,
  .localGet objectResultLocal]

private def retypeAddress : List Instruction :=
  retypeAddressValue ++ [.ret]

private def retypeAddressTObject : List Instruction := [
  .i32Const .uint32 0,
  .i32Load .uint32 0,
  .localSet savedScratchLocal,
  .i32Const .uint32 0,
  .localGet addressLocal,
  .i32Store .uint32 0,
  .i32Const .uint32 0,
  .i32Load .tobject 0,
  .localSet tobjectResultLocal,
  .i32Const .uint32 0,
  .localGet savedScratchLocal,
  .i32Store .uint32 0,
  .localGet tobjectResultLocal,
  .ret]

private def checkedInputAddress : List Instruction := [
  .i32Const .uint32 0,
  .i32Load .uint32 0,
  .localSet savedScratchLocal,
  .i32Const .uint32 0,
  .localGet arrayParam,
  .i32Store .object 0,
  .i32Const .uint32 0,
  .i32Load .uint32 0,
  .localSet inputAddressLocal,
  .i32Const .uint32 0,
  .localGet savedScratchLocal,
  .i32Store .uint32 0]

/-
Typed closed applications already carry the resident Array representation
invariant. Preserve the raw/public scratch retype, but let the trusted path use
the same typed extend/wrap bridge as the accepted direct Nat/USize result
paths. Binaryen erases the bridge to the physical i32 word, so exclusive Array
updates no longer touch scratch memory before testing uniqueness.
-/
private def trustedInputAddress : List Instruction := [
  .localGet arrayParam,
  .i64ExtendI32U .uint64,
  .i32WrapI64 .uint32,
  .localSet inputAddressLocal]

private def captureInputAddress (validation : InputValidation) :
    List Instruction :=
  match validation with
  | .checked => checkedInputAddress
  | .trusted => trustedInputAddress

private def retypeTagged : List Instruction := [
  .i32Const .uint32 0,
  .i32Load .uint32 0,
  .localSet savedScratchLocal,
  .i32Const .uint32 0,
  .localGet rawLocal,
  .i32Store .uint32 0,
  .i32Const .uint32 0,
  .i32Load .tagged 0,
  .localSet taggedResultLocal,
  .i32Const .uint32 0,
  .localGet savedScratchLocal,
  .i32Store .uint32 0,
  .localGet taggedResultLocal,
  .ret]

private def allocationBytesBody : List Instruction := [
  .localGet capacityLocal,
  .localGet capacityLocal,
  .i32Add,
  .localSet allocationBytesLocal] ++
  trapWhenTrue [
    .localGet allocationBytesLocal,
    .localGet capacityLocal,
    .i32LtU] ++ [
  .localGet allocationBytesLocal,
  .localSet countLocal,
  .localGet countLocal,
  .localGet countLocal,
  .i32Add,
  .localSet allocationBytesLocal] ++
  trapWhenTrue [
    .localGet allocationBytesLocal,
    .localGet countLocal,
    .i32LtU] ++ [
  .localGet allocationBytesLocal,
  .localSet countLocal,
  .localGet countLocal,
  .localGet countLocal,
  .i32Add,
  .localSet allocationBytesLocal] ++
  trapWhenTrue [
    .localGet allocationBytesLocal,
    .localGet countLocal,
    .i32LtU] ++ [
  .localGet allocationBytesLocal,
  .localSet countLocal,
  .localGet allocationBytesLocal,
  .i32Const .uint32 (u32 headerBytes),
  .i32Add,
  .localSet allocationBytesLocal] ++
  trapWhenTrue [
    .localGet allocationBytesLocal,
    .localGet countLocal,
    .i32LtU]

private def decodeCapacity : List Instruction := [
  .localGet capacityParam,
  .call (.declaration ResidentNumeric.validateNaturalName),
  .localGet capacityParam,
  .call (.declaration ResidentNumeric.naturalHighName),
  .i32Const .uint32 0,
  .i32Eq,
  .ifElse [] [.unreachable],
  .localGet capacityParam,
  .call (.declaration ResidentNumeric.naturalLowName),
  .localSet capacityLocal]

def allocateEmptyFunction : Function := {
  name := allocateEmptyName
  params := #[(capacityParam, .uint32)]
  results := #[.object]
  locals := #[(addressLocal, .uint32), (capacityLocal, .uint32),
    (countLocal, .uint32), (allocationBytesLocal, .uint32),
    (savedScratchLocal, .uint32), (objectResultLocal, .object)]
  body := [
    .localGet capacityParam,
    .localSet capacityLocal] ++ allocationBytesBody ++ [
    .localGet allocationBytesLocal,
    .call (.declaration ResidentAllocator.allocateName),
    .localSet addressLocal] ++
    initializeHeader [.i32Const .uint32 0] [.localGet capacityLocal] ++
    retypeAddress }

/-- Allocate the ordinary resident representation of `List.cons`. The helper
consumes the owned head and tail references supplied by its caller. -/
def allocateListConsFunction : Function := {
  name := allocateListConsName
  params := #[(valueParam, .tobject), (tailParam, .tobject)]
  results := #[.tobject]
  locals := #[(addressLocal, .uint32), (savedScratchLocal, .uint32),
    (tobjectResultLocal, .tobject)]
  body := [
    .i32Const .uint32 (u32 listConsAllocationBytes),
    .call (.declaration ResidentAllocator.allocateName),
    .localSet addressLocal] ++
    storeHeaderWord headerKindOffset
      [.i32Const .uint32 ObjectKind.constructor.code] ++
    storeHeaderWord headerFlagsOffset [.i32Const .uint32 liveFlag] ++
    storeHeaderWord headerRefCountOffset [.i32Const .uint32 1] ++
    storeHeaderWord headerAllocationBytesOffset
      [.i32Const .uint32 (u32 listConsAllocationBytes)] ++
    storeHeaderWord headerAux0Offset [.i32Const .uint32 1] ++
    storeHeaderWord headerAux1Offset [.i32Const .uint32 2] ++
    storeHeaderWord headerAux2Offset [.i32Const .uint32 0] ++
    storeHeaderWord headerAux3Offset [.i32Const .uint32 0] ++
    storeObjectWord addressLocal valueParam headerBytes ++
    storeObjectWord addressLocal tailParam
      (headerBytes + target.semanticSlotBytes) ++
    retypeAddressTObject }

private def sizeFunctionFor (validation : InputValidation) : Function := {
  name := externalName `Array.size
  params := #[(erasedParam, .erased), (arrayParam, .object)]
  results := #[.tagged]
  locals := #[(sizeLocal, .uint32), (rawLocal, .uint32),
    (savedScratchLocal, .uint32), (taggedResultLocal, .tagged)]
  body := validateArrayInput validation arrayParam ++ loadSize arrayParam ++ [
    .localGet sizeLocal,
    .localGet sizeLocal,
    .i32Add,
    .i32Const .uint32 1,
    .i32Add,
    .localSet rawLocal] ++ retypeTagged }

def sizeFunction : Function := sizeFunctionFor .checked

private def usizeFunctionFor (validation : InputValidation) : Function := {
  name := externalName `Array.usize
  params := #[(erasedParam, .erased), (arrayParam, .object)]
  results := #[.usize]
  locals := #[(sizeLocal, .uint32)]
  body := validateArrayInput validation arrayParam ++ loadSize arrayParam ++ [
    .localGet sizeLocal,
    .i64ExtendI32U .usize,
    .ret] }

def usizeFunction : Function := usizeFunctionFor .checked

private def countInputList : List Instruction := [
  .localGet listParam,
  .localSet listLocal,
  .i32Const .uint32 0,
  .localSet countLocal,
  .loop listCountLoopLabel ([
    .localGet listLocal,
    .i32Const .uint32 1,
    .i32And,
    .ifElse
      (trapUnless ([.localGet listLocal] ++ equalsConst .tobject 1))
      (requireListCons listLocal ++ [
        .localGet countLocal,
        .i32Const .uint32 1,
        .i32Add,
        .localSet countLocal] ++
        trapWhenTrue ([.localGet countLocal] ++ equalsConst .uint32 0) ++ [
        .localGet listLocal,
        .i32Load .tobject
          (u32 (headerBytes + target.semanticSlotBytes)),
        .localSet listLocal,
        .br listCountLoopLabel])]),
  .localGet countLocal,
  .localSet sizeLocal]

/-- Fill a freshly allocated Array while consuming the input List one node at
a time. Retaining both fields before decrementing the node makes the operation
correct for unique, shared, and persistent List spines without recursive tail
release. -/
private def consumeListIntoArray : List Instruction := [
  .localGet listParam,
  .localSet listLocal,
  .localGet addressLocal,
  .i32Const .uint32 (u32 headerBytes),
  .i32Add,
  .localSet targetCursorLocal,
  .i32Const .uint32 0,
  .localSet countLocal,
  .loop listFillLoopLabel [
    .localGet countLocal,
    .localGet sizeLocal,
    .i32LtU,
    .ifElse (requireListCons listLocal ++ [
      .localGet listLocal,
      .i32Load .tobject (u32 headerBytes),
      .localSet elementLocal,
      .localGet listLocal,
      .i32Load .tobject (u32 (headerBytes + target.semanticSlotBytes)),
      .localSet tailLocal,
      .localGet elementLocal,
      .call (.declaration ResidentReferenceCount.incrementOnceName),
      .localGet tailLocal,
      .call (.declaration ResidentReferenceCount.incrementOnceName)] ++
      ResidentRelease.checkedDecrementLocal listLocal ++
      storeObjectWord targetCursorLocal elementLocal ++ [
      .localGet targetCursorLocal,
      .i32Const .uint32 (u32 target.semanticSlotBytes),
      .i32Add,
      .localSet targetCursorLocal,
      .localGet tailLocal,
      .localSet listLocal,
      .localGet countLocal,
      .i32Const .uint32 1,
      .i32Add,
      .localSet countLocal,
      .br listFillLoopLabel]) []]] ++
  trapUnless ([.localGet listLocal] ++ equalsConst .tobject 1)

/-- Resident implementation of the upstream `Array.mk` extern. -/
def mkFunction : Function := {
  name := externalName `Array.mk
  params := #[(erasedParam, .erased), (listParam, .tobject)]
  results := #[.object]
  locals := #[(addressLocal, .uint32), (sizeLocal, .uint32),
    (capacityLocal, .uint32), (countLocal, .uint32),
    (targetCursorLocal, .uint32), (allocationBytesLocal, .uint32),
    (elementLocal, .tobject), (listLocal, .tobject),
    (tailLocal, .tobject), (savedScratchLocal, .uint32),
    (objectResultLocal, .object)]
  body := countInputList ++ [
    .localGet sizeLocal,
    .localSet capacityLocal] ++ allocationBytesBody ++ [
    .localGet allocationBytesLocal,
    .call (.declaration ResidentAllocator.allocateName),
    .localSet addressLocal] ++
    initializeHeader [.localGet sizeLocal] [.localGet capacityLocal] ++
    consumeListIntoArray ++ retypeAddress }

private def advanceToArrayEnd : List Instruction := [
  .localGet arrayParam,
  .i32Const .uint32 (u32 headerBytes),
  .i32Add,
  .localSet sourceCursorLocal,
  .i32Const .uint32 0,
  .localSet countLocal,
  .loop arrayListCursorLoopLabel [
    .localGet countLocal,
    .localGet sizeLocal,
    .i32LtU,
    .ifElse [
      .localGet sourceCursorLocal,
      .i32Const .uint32 (u32 target.semanticSlotBytes),
      .i32Add,
      .localSet sourceCursorLocal,
      .localGet countLocal,
      .i32Const .uint32 1,
      .i32Add,
      .localSet countLocal,
      .br arrayListCursorLoopLabel] []]]

private def buildListFromArray : List Instruction := [
  .i32Const .tobject 1,
  .localSet listLocal,
  .localGet sizeLocal,
  .localSet countLocal,
  .loop arrayToListLoopLabel [
    .i32Const .uint32 0,
    .localGet countLocal,
    .i32LtU,
    .ifElse [
      .localGet countLocal,
      .i32Const .uint32 1,
      .i32Sub,
      .localSet countLocal,
      .localGet sourceCursorLocal,
      .i32Const .uint32 (u32 target.semanticSlotBytes),
      .i32Sub,
      .localSet sourceCursorLocal,
      .localGet sourceCursorLocal,
      .i32Load .tobject 0,
      .localSet elementLocal,
      .localGet elementLocal,
      .call (.declaration ResidentReferenceCount.incrementOnceName),
      .localGet elementLocal,
      .localGet listLocal,
      .call (.declaration allocateListConsName),
      .localSet listLocal,
      .br arrayToListLoopLabel] []]]

/-- Resident implementation of the upstream `Array.toList` extern. -/
private def toListFunctionFor (validation : InputValidation) : Function := {
  name := externalName `Array.toList
  params := #[(erasedParam, .erased), (arrayParam, .object)]
  results := #[.tobject]
  locals := #[(sizeLocal, .uint32), (countLocal, .uint32),
    (sourceCursorLocal, .uint32), (elementLocal, .tobject),
    (listLocal, .tobject)]
  body := validateArrayInput validation arrayParam ++ loadSize arrayParam ++
    advanceToArrayEnd ++ buildListFromArray ++ [
    .localGet arrayParam,
    .i32Const .uint32 1,
    .call (.declaration ResidentRelease.decrementOnceName),
    .localGet listLocal,
    .ret] }

def toListFunction : Function := toListFunctionFor .checked

private def elementAddressFor (array index cursor : FVarId) :
    List Instruction :=
  /- `semanticSlotBytes` is the fixed W6 object-lane width. Compute
  `array + headerBytes + index * 8` in constant time with three doublings;
  the symbolic instruction layer does not otherwise need an `i32.mul`. -/
  [.localGet index,
    .localSet cursor] ++
  (List.range 3).flatMap (fun _ => [
    .localGet cursor,
    .localGet cursor,
    .i32Add,
    .localSet cursor]) ++
  [.localGet array,
    .i32Const .uint32 (u32 headerBytes),
    .i32Add,
    .localGet cursor,
    .i32Add,
    .localSet cursor]

#guard target.semanticSlotBytes == 8

private partial def containsLoop : Instruction → Bool
  | .loop _ _ => true
  | .block _ body => body.any containsLoop
  | .ifElse thenBody elseBody =>
      thenBody.any containsLoop || elseBody.any containsLoop
  | _ => false

#guard !(elementAddressFor arrayParam indexParam sourceCursorLocal).any containsLoop

private def elementAddress : List Instruction :=
  elementAddressFor arrayParam indexLocal sourceCursorLocal

private def getBangBody (validation : InputValidation) (owned : Bool) :
    List Instruction :=
  validateArrayInput validation arrayParam ++ loadSize arrayParam ++ decodeIndex ++ [
    .localGet indexLocal,
    .localGet sizeLocal,
    .i32LtU,
    .ifElse
      (elementAddress ++ [
        .localGet sourceCursorLocal,
        .i32Load .tobject 0,
        .localSet elementLocal] ++
        (if owned then [
          .localGet elementLocal,
          .call (.declaration ResidentReferenceCount.incrementOnceName)]
        else []) ++ [
        .localGet elementLocal,
        .ret])
      [.localGet defaultParam,
        .call (.declaration ResidentReferenceCount.incrementOnceName),
        .localGet defaultParam,
        .ret]]

private def proofGetBody (inputValidation : InputValidation)
    (proofIndexValidation : ProofIndexValidation) (owned : Bool) :
    List Instruction :=
  validateArrayInput inputValidation arrayParam ++
    (match proofIndexValidation with
    | .checked => loadSize arrayParam
    | .trusted => []) ++
    decodeProofNaturalIndex proofIndexValidation indexParam indexLocal ++
    elementAddress ++ [
      .localGet sourceCursorLocal,
      .i32Load .tobject 0,
      .localSet elementLocal] ++
    (if owned then [
      .localGet elementLocal,
      .call (.declaration ResidentReferenceCount.incrementOnceName)]
    else []) ++ [
      .localGet elementLocal,
      .ret]

private def getBangFunction (validation : InputValidation)
    (declaration : Name) (owned : Bool) : Function := {
  name := externalName declaration
  params := #[(erasedParam, .erased), (defaultParam, .tobject),
    (arrayParam, .object), (indexParam, .tobject)]
  results := #[.tobject]
  locals := #[(sizeLocal, .uint32), (indexLocal, .uint32),
    (countLocal, .uint32), (sourceCursorLocal, .uint32),
    (elementLocal, .tobject)]
  body := getBangBody validation owned }

def getBangBorrowedFunction : Function :=
  getBangFunction .checked `Array.get!InternalBorrowed false

def getBangOwnedFunction : Function :=
  getBangFunction .checked `Array.get!Internal true

private def getBorrowedFunctionFor (inputValidation : InputValidation)
    (proofIndexValidation : ProofIndexValidation) : Function := {
  name := externalName `Array.getInternalBorrowed
  params := #[(erasedParam, .erased), (arrayParam, .object),
    (indexParam, .tobject), (proofParam, .erased)]
  results := #[.tobject]
  locals := #[(sizeLocal, .uint32), (indexLocal, .uint32),
    (countLocal, .uint32), (sourceCursorLocal, .uint32),
    (elementLocal, .tobject)]
  body := proofGetBody inputValidation proofIndexValidation false }

def getBorrowedFunction : Function :=
  getBorrowedFunctionFor .checked .checked

private def getFunctionFor (inputValidation : InputValidation)
    (proofIndexValidation : ProofIndexValidation) : Function := {
  name := externalName `Array.getInternal
  params := #[(erasedParam, .erased), (arrayParam, .object),
    (indexParam, .tobject), (proofParam, .erased)]
  results := #[.tobject]
  locals := #[(sizeLocal, .uint32), (indexLocal, .uint32),
    (countLocal, .uint32), (sourceCursorLocal, .uint32),
    (elementLocal, .tobject)]
  body := proofGetBody inputValidation proofIndexValidation true }

def getFunction : Function := getFunctionFor .checked .checked

private def ugetBorrowedFunctionFor (inputValidation : InputValidation)
    (proofIndexValidation : ProofIndexValidation) : Function := {
  name := externalName `Array.ugetBorrowed
  params := #[(erasedParam, .erased), (arrayParam, .object),
    (indexParam, .usize), (proofParam, .erased)]
  results := #[.tobject]
  locals := #[(sizeLocal, .uint32), (indexLocal, .uint32),
    (countLocal, .uint32), (sourceCursorLocal, .uint32)]
  body := validateArrayInput inputValidation arrayParam ++
    (match proofIndexValidation with
    | .checked => loadSize arrayParam
    | .trusted => []) ++
    decodeProofUSizeIndex proofIndexValidation indexParam indexLocal ++
    elementAddress ++ [
    .localGet sourceCursorLocal,
    .i32Load .tobject 0,
    .ret] }

def ugetBorrowedFunction : Function :=
  ugetBorrowedFunctionFor .checked .checked

private def ugetFunctionFor (inputValidation : InputValidation)
    (proofIndexValidation : ProofIndexValidation) : Function := {
  name := externalName `Array.uget
  params := #[(erasedParam, .erased), (arrayParam, .object),
    (indexParam, .usize), (proofParam, .erased)]
  results := #[.tobject]
  locals := #[(sizeLocal, .uint32), (indexLocal, .uint32),
    (countLocal, .uint32), (sourceCursorLocal, .uint32),
    (elementLocal, .tobject)]
  body := validateArrayInput inputValidation arrayParam ++
    (match proofIndexValidation with
    | .checked => loadSize arrayParam
    | .trusted => []) ++
    decodeProofUSizeIndex proofIndexValidation indexParam indexLocal ++
    elementAddress ++ [
    .localGet sourceCursorLocal,
    .i32Load .tobject 0,
    .localSet elementLocal,
    .localGet elementLocal,
    .call (.declaration ResidentReferenceCount.incrementOnceName),
    .localGet elementLocal,
    .ret] }

def ugetFunction : Function := ugetFunctionFor .checked .checked

private def validatorDelta (checked trusted : Function) : Bool :=
  let validation := requireArray arrayParam
  checked.body.take validation.length == validation &&
    checked.body.drop validation.length == trusted.body

#guard validatorDelta (sizeFunctionFor .checked) (sizeFunctionFor .trusted)
#guard validatorDelta (usizeFunctionFor .checked) (usizeFunctionFor .trusted)
#guard validatorDelta
  (getBangFunction .checked `Array.get!InternalBorrowed false)
  (getBangFunction .trusted `Array.get!InternalBorrowed false)
#guard validatorDelta
  (getBangFunction .checked `Array.get!Internal true)
  (getBangFunction .trusted `Array.get!Internal true)
#guard validatorDelta (toListFunctionFor .checked) (toListFunctionFor .trusted)

private def emptyWrapper (declaration : Name) : Function := {
  name := externalName declaration
  params := #[(erasedParam, .erased), (capacityParam, .tobject)]
  results := #[.object]
  locals := #[(capacityLocal, .uint32)]
  body := decodeCapacity ++ [
    .localGet capacityLocal,
    .call (.declaration allocateEmptyName),
    .ret] }

def emptyWithCapacityFunction : Function :=
  emptyWrapper `Array.emptyWithCapacity

def mkEmptyFunction : Function := emptyWrapper `Array.mkEmpty

private def copyElementsBody (retain : Bool)
    (loopLabel : FVarId := copyLoopLabel) : List Instruction := [
  .localGet arrayParam,
  .i32Const .uint32 (u32 headerBytes),
  .i32Add,
  .localSet sourceCursorLocal,
  .localGet addressLocal,
  .i32Const .uint32 (u32 headerBytes),
  .i32Add,
  .localSet targetCursorLocal,
  .i32Const .uint32 0,
  .localSet countLocal,
  .loop loopLabel [
    .localGet countLocal,
    .localGet sizeLocal,
    .i32LtU,
    .ifElse ([
      .localGet sourceCursorLocal,
      .i32Load .tobject 0,
      .localSet elementLocal] ++
      (if retain then [
        .localGet elementLocal,
        .call (.declaration ResidentReferenceCount.incrementOnceName)]
      else []) ++ storeObjectWord targetCursorLocal elementLocal ++ [
      .localGet sourceCursorLocal,
      .i32Const .uint32 (u32 target.semanticSlotBytes),
      .i32Add,
      .localSet sourceCursorLocal,
      .localGet targetCursorLocal,
      .i32Const .uint32 (u32 target.semanticSlotBytes),
      .i32Add,
      .localSet targetCursorLocal,
      .localGet countLocal,
      .i32Const .uint32 1,
      .i32Add,
      .localSet countLocal,
      .br loopLabel]) []]]

private def checkedSelectExclusive : List Instruction := [
  .i32Const .uint32 0,
  .localSet exclusiveLocal,
  .localGet arrayParam,
  .i32Load .uint32 (u32 headerFlagsOffset)] ++
  equalsConst .uint32 liveFlag ++ [
  .ifElse (
    [.localGet arrayParam,
      .i32Load .uint32 (u32 headerRefCountOffset)] ++
    equalsConst .uint32 1 ++ [
      .ifElse [
        .i32Const .uint32 1,
        .localSet exclusiveLocal] []]) []]

/- `lean_is_exclusive` classifies a valid runtime object by its reference
count. The trusted resident Array invariant already excludes malformed flag /
reference-count combinations, so its hot mutation path can do the same single
header load. Raw/public helpers retain the explicit flag check. -/
private def trustedSelectExclusive : List Instruction := [
  .localGet arrayParam,
  .i32Load .uint32 (u32 headerRefCountOffset)] ++
  equalsConst .uint32 1 ++ [
  .localSet exclusiveLocal]

private def selectExclusive (validation : InputValidation) : List Instruction :=
  match validation with
  | .checked => checkedSelectExclusive
  | .trusted => trustedSelectExclusive

/--
Retire an exclusive Array whose element ownership has moved to a replacement
allocation.  This is header-only retirement: the payload must not be released
recursively, but the complete dead allocation remains eligible for resident
exact-size reuse.
-/
def retireTransferredArray : List Instruction := [
  .localGet inputAddressLocal,
  .i32Const .uint32 ObjectKind.freed.code,
  .i32Store .uint32 (u32 headerKindOffset),
  .localGet inputAddressLocal,
  .i32Const .uint32 0,
  .i32Store .uint32 (u32 headerFlagsOffset),
  .localGet inputAddressLocal,
  .i32Const .uint32 0,
  .i32Store .uint32 (u32 headerRefCountOffset),
  .localGet inputAddressLocal,
  .i32Const .uint32 0,
  .i32Store .uint32 (u32 headerAux0Offset),
  .localGet inputAddressLocal,
  .i32Const .uint32 0,
  .i32Store .uint32 (u32 headerAux1Offset),
  .localGet inputAddressLocal,
  .i32Const .uint32 0,
  .i32Store .uint32 (u32 headerAux2Offset),
  .localGet inputAddressLocal,
  .i32Const .uint32 0,
  .i32Store .uint32 (u32 headerAux3Offset),
  .localGet inputAddressLocal,
  .call (.declaration ResidentAllocator.recycleName)]

private def consumeSharedArray : List Instruction := [
  .localGet arrayParam,
  .i32Load .uint32 (u32 headerFlagsOffset),
  .i32Const .uint32 persistentFlag,
  .i32And] ++ equalsConst .uint32 persistentFlag ++ [
  .ifElse [] ([
    .localGet inputAddressLocal,
    .i32Load .uint32 (u32 headerRefCountOffset),
    .localSet refCountLocal] ++
    trapUnless [
      .i32Const .uint32 1,
      .localGet refCountLocal,
      .i32LtU] ++ [
    .localGet inputAddressLocal,
    .localGet refCountLocal,
    .i32Const .uint32 1,
    .i32Sub,
    .i32Store .uint32 (u32 headerRefCountOffset)])]

private def growCapacityBody : List Instruction := [
  .localGet capacityLocal,
  .i32Const .uint32 1,
  .i32Add,
  .localSet countLocal] ++
  trapWhenTrue [
    .localGet countLocal,
    .localGet capacityLocal,
    .i32LtU] ++ [
  .localGet countLocal,
  .localGet countLocal,
  .i32Add,
  .localSet newCapacityLocal] ++
  trapWhenTrue [
    .localGet newCapacityLocal,
    .localGet countLocal,
    .i32LtU]

private def sharedPushCapacityBody : List Instruction := [
  .localGet sizeLocal,
  .localGet sizeLocal,
  .i32Add,
  .localSet countLocal] ++
  trapWhenTrue [
    .localGet countLocal,
    .localGet sizeLocal,
    .i32LtU] ++ [
  .localGet countLocal,
  .i32Const .uint32 1,
  .i32Add,
  .localSet countLocal] ++
  trapWhenTrue ([.localGet countLocal] ++ equalsConst .uint32 0) ++ [
  .localGet capacityLocal,
  .localSet newCapacityLocal,
  .localGet capacityLocal,
  .localGet countLocal,
  .i32LtU,
  .ifElse growCapacityBody []]

private def selectReusablePush : List Instruction := [
  .i32Const .uint32 0,
  .localSet reuseLocal,
  .localGet exclusiveLocal,
  .ifElse [
    .localGet sizeLocal,
    .localGet capacityLocal,
    .i32LtU,
    .ifElse [
      .i32Const .uint32 1,
      .localSet reuseLocal] []] []]

private def pushInPlaceValue : List Instruction := [
  .localGet sizeLocal,
  .localSet indexLocal] ++ elementAddress ++
  storeObjectWord sourceCursorLocal valueParam ++ [
  .localGet inputAddressLocal,
  .localGet sizeLocal,
  .i32Const .uint32 1,
  .i32Add,
  .i32Store .uint32 (u32 headerAux1Offset),
  .localGet arrayParam,
  .localSet objectResultLocal]

private def pushAllocatedValue : List Instruction := [
  .localGet exclusiveLocal,
  .ifElse growCapacityBody sharedPushCapacityBody,
  .localGet newCapacityLocal,
  .localSet capacityLocal] ++ allocationBytesBody ++ [
  .localGet allocationBytesLocal,
  .call (.declaration ResidentAllocator.allocateName),
  .localSet addressLocal] ++
  initializeHeader
    [.localGet sizeLocal, .i32Const .uint32 1, .i32Add]
    [.localGet capacityLocal] ++ [
  .localGet exclusiveLocal,
  .ifElse
    (copyElementsBody false ++ retireTransferredArray)
    (copyElementsBody true retainedCopyLoopLabel ++ consumeSharedArray)] ++
  storeObjectWord targetCursorLocal valueParam ++
  retypeAddressValue ++ [.localSet objectResultLocal]

private def pushFunctionFor (validation : InputValidation) : Function := {
  name := externalName `Array.push
  params := #[(erasedParam, .erased), (arrayParam, .object),
    (valueParam, .tobject)]
  results := #[.object]
  locals := #[(addressLocal, .uint32), (sizeLocal, .uint32),
    (inputAddressLocal, .uint32),
    (capacityLocal, .uint32), (newCapacityLocal, .uint32),
    (exclusiveLocal, .uint32), (reuseLocal, .uint32),
    (refCountLocal, .uint32),
    (indexLocal, .uint32), (countLocal, .uint32),
    (sourceCursorLocal, .uint32),
    (targetCursorLocal, .uint32), (allocationBytesLocal, .uint32),
    (savedScratchLocal, .uint32), (objectResultLocal, .object),
    (elementLocal, .tobject)]
  body := validateArrayInput validation arrayParam ++
    captureInputAddress validation ++
    loadSize arrayParam ++
    loadCapacity arrayParam ++ selectExclusive validation ++
    selectReusablePush ++ [
    .localGet reuseLocal,
    .ifElse pushInPlaceValue pushAllocatedValue,
    .localGet objectResultLocal,
    .ret] }

def pushFunction : Function := pushFunctionFor .checked

/-- Reference-counted implementation of upstream `Array.pop`. -/
private def popFunctionFor (validation : InputValidation) : Function := {
  name := externalName `Array.pop
  params := #[(erasedParam, .erased), (arrayParam, .object)]
  results := #[.object]
  locals := #[(addressLocal, .uint32), (sizeLocal, .uint32),
    (inputAddressLocal, .uint32),
    (capacityLocal, .uint32), (exclusiveLocal, .uint32),
    (refCountLocal, .uint32), (indexLocal, .uint32),
    (countLocal, .uint32), (sourceCursorLocal, .uint32),
    (targetCursorLocal, .uint32), (allocationBytesLocal, .uint32),
    (savedScratchLocal, .uint32), (objectResultLocal, .object),
    (elementLocal, .tobject)]
  body := validateArrayInput validation arrayParam ++
    captureInputAddress validation ++
    loadSize arrayParam ++
    loadCapacity arrayParam ++ selectExclusive validation ++ [
    .localGet exclusiveLocal,
    .ifElse ([.localGet sizeLocal] ++ equalsConst .uint32 0 ++ [
      .ifElse [.localGet arrayParam, .ret] [],
      .localGet sizeLocal,
      .i32Const .uint32 1,
      .i32Sub,
      .localSet sizeLocal,
      .localGet sizeLocal,
      .localSet indexLocal] ++ elementAddress ++ [
      .localGet sourceCursorLocal,
      .i32Load .tobject 0,
      .localSet elementLocal,
      .localGet inputAddressLocal,
      .localGet sizeLocal,
      .i32Store .uint32 (u32 headerAux1Offset)] ++
      ResidentRelease.checkedDecrementLocal elementLocal ++ [
      .localGet arrayParam,
      .ret]) [],
    .localGet sizeLocal] ++ equalsConst .uint32 0 ++ [
    .ifElse [] [
      .localGet sizeLocal,
      .i32Const .uint32 1,
      .i32Sub,
      .localSet sizeLocal]] ++ allocationBytesBody ++ [
    .localGet allocationBytesLocal,
    .call (.declaration ResidentAllocator.allocateName),
    .localSet addressLocal] ++
    initializeHeader [.localGet sizeLocal] [.localGet capacityLocal] ++
    copyElementsBody true ++ consumeSharedArray ++ retypeAddress }

def popFunction : Function := popFunctionFor .checked

private def copyUpdatedElementsBody : List Instruction := [
  .localGet arrayParam,
  .i32Const .uint32 (u32 headerBytes),
  .i32Add,
  .localSet sourceCursorLocal,
  .localGet addressLocal,
  .i32Const .uint32 (u32 headerBytes),
  .i32Add,
  .localSet targetCursorLocal,
  .i32Const .uint32 0,
  .localSet countLocal,
  .loop copyLoopLabel [
    .localGet countLocal,
    .localGet sizeLocal,
    .i32LtU,
    .ifElse [
      .localGet sourceCursorLocal,
      .i32Load .tobject 0,
      .localSet elementLocal,
      .localGet countLocal,
      .localGet indexLocal,
      .i32Eq,
      .ifElse
        (storeObjectWord targetCursorLocal valueParam)
        ([
        .localGet elementLocal,
        .call (.declaration ResidentReferenceCount.incrementOnceName)] ++
        storeObjectWord targetCursorLocal elementLocal),
      .localGet sourceCursorLocal,
      .i32Const .uint32 (u32 target.semanticSlotBytes),
      .i32Add,
      .localSet sourceCursorLocal,
      .localGet targetCursorLocal,
      .i32Const .uint32 (u32 target.semanticSlotBytes),
      .i32Add,
      .localSet targetCursorLocal,
      .localGet countLocal,
      .i32Const .uint32 1,
      .i32Add,
      .localSet countLocal,
      .br copyLoopLabel] []]]

private def replaceExclusiveElementBody : List Instruction :=
  elementAddress ++ [
    .localGet sourceCursorLocal,
    .i32Load .tobject 0,
    .localSet elementLocal] ++
    ResidentRelease.checkedDecrementLocal elementLocal ++
    storeObjectWord sourceCursorLocal valueParam ++ [
    .localGet arrayParam,
    .ret]

-- Match upstream `lean_array_uset`: release the displaced owner before the
-- consumed replacement becomes reachable from the Array.
#guard replaceExclusiveElementBody ==
  elementAddress ++ [
    .localGet sourceCursorLocal,
    .i32Load .tobject 0,
    .localSet elementLocal] ++
    ResidentRelease.checkedDecrementLocal elementLocal ++
    storeObjectWord sourceCursorLocal valueParam ++ [
    .localGet arrayParam,
    .ret]

private def replaceSharedArrayBody : List Instruction :=
  allocationBytesBody ++ [
    .localGet allocationBytesLocal,
    .call (.declaration ResidentAllocator.allocateName),
    .localSet addressLocal] ++
    initializeHeader [.localGet sizeLocal] [.localGet capacityLocal] ++
    copyUpdatedElementsBody ++ consumeSharedArray ++ retypeAddress

private def checkedReplaceAtDecodedIndexBody : List Instruction :=
  loadCapacity arrayParam ++ selectExclusive .checked ++ [
    .localGet exclusiveLocal,
    .ifElse replaceExclusiveElementBody []] ++ replaceSharedArrayBody

private def trustedReplaceAtDecodedIndexPrefix : List Instruction := [
  .localGet arrayParam,
  .i32Load .uint32 (u32 headerRefCountOffset),
  .i32Const .uint32 1,
  .i32Eq,
  .ifElse replaceExclusiveElementBody []]

private def trustedReplaceAtDecodedIndexBody : List Instruction :=
  trustedReplaceAtDecodedIndexPrefix ++ loadCapacity arrayParam ++
    replaceSharedArrayBody

private def replaceAtDecodedIndexBody (validation : InputValidation) :
    List Instruction :=
  match validation with
  | .checked => checkedReplaceAtDecodedIndexBody
  | .trusted => trustedReplaceAtDecodedIndexBody

#guard replaceAtDecodedIndexBody .checked == checkedReplaceAtDecodedIndexBody
#guard (replaceAtDecodedIndexBody .trusted).take
    trustedReplaceAtDecodedIndexPrefix.length ==
      trustedReplaceAtDecodedIndexPrefix
#guard (replaceAtDecodedIndexBody .trusted).drop
    trustedReplaceAtDecodedIndexPrefix.length ==
      loadCapacity arrayParam ++ replaceSharedArrayBody

private def setLocals : Array (FVarId × AbiKind) := #[(addressLocal, .uint32),
  (sizeLocal, .uint32), (inputAddressLocal, .uint32),
  (capacityLocal, .uint32), (exclusiveLocal, .uint32),
  (refCountLocal, .uint32), (indexLocal, .uint32),
  (countLocal, .uint32), (sourceCursorLocal, .uint32),
  (targetCursorLocal, .uint32), (allocationBytesLocal, .uint32),
  (savedScratchLocal, .uint32), (objectResultLocal, .object),
  (elementLocal, .tobject)]

private def usetFunctionFor (inputValidation : InputValidation)
    (proofIndexValidation : ProofIndexValidation) : Function := {
  name := externalName `Array.uset
  params := #[(erasedParam, .erased), (arrayParam, .object),
    (indexParam, .usize), (valueParam, .tobject), (proofParam, .erased)]
  results := #[.object]
  locals := setLocals
  body := validateArrayInput inputValidation arrayParam ++
    captureInputAddress inputValidation ++
    loadSize arrayParam ++
    decodeProofUSizeIndex proofIndexValidation indexParam indexLocal ++
    replaceAtDecodedIndexBody inputValidation }

def usetFunction : Function := usetFunctionFor .checked .checked

private def setFunctionFor (inputValidation : InputValidation)
    (proofIndexValidation : ProofIndexValidation) : Function := {
  name := externalName `Array.set
  params := #[(erasedParam, .erased), (arrayParam, .object),
    (indexParam, .tobject), (valueParam, .tobject), (proofParam, .erased)]
  results := #[.object]
  locals := setLocals
  body := validateArrayInput inputValidation arrayParam ++
    captureInputAddress inputValidation ++
    loadSize arrayParam ++
    decodeProofNaturalIndex proofIndexValidation indexParam indexLocal ++
    replaceAtDecodedIndexBody inputValidation }

def setFunction : Function := setFunctionFor .checked .checked

private def trustedSetCallSiteRewrite : ResidentCallSite.Rewrite := {
  target := .declaration `Array.set
  signature := {
    params := #[.erased, .object, .tobject, .tobject, .erased]
    results := #[.object] }
  locals := #[(inlineSetErasedLocal, .erased),
    (inlineSetArrayLocal, .object), (inlineSetIndexParamLocal, .tobject),
    (inlineSetValueLocal, .tobject), (inlineSetIndexLocal, .uint32),
    (inlineSetCursorLocal, .uint32), (inlineSetElementLocal, .tobject),
    (inlineSetResultLocal, .object)]
  body := [
    .localSet inlineSetErasedLocal,
    .localSet inlineSetValueLocal,
    .localSet inlineSetIndexParamLocal,
    .localSet inlineSetArrayLocal,
    .localSet inlineSetErasedLocal,
    .localGet inlineSetArrayLocal,
    .i32Load .uint32 (u32 headerRefCountOffset),
    .i32Const .uint32 1,
    .i32Eq,
    .ifElse
      (decodeTrustedNaturalIndex inlineSetIndexParamLocal inlineSetIndexLocal ++
        elementAddressFor inlineSetArrayLocal inlineSetIndexLocal
          inlineSetCursorLocal ++ [
        .localGet inlineSetCursorLocal,
        .i32Load .tobject 0,
        .localSet inlineSetElementLocal,
        ] ++ storeObjectWord inlineSetCursorLocal inlineSetValueLocal ++
        ResidentRelease.checkedDecrementLocal inlineSetElementLocal ++ [
        .localGet inlineSetArrayLocal,
        .localSet inlineSetResultLocal])
      [.localGet inlineSetErasedLocal,
        .localGet inlineSetArrayLocal,
        .localGet inlineSetIndexParamLocal,
        .localGet inlineSetValueLocal,
        .localGet inlineSetErasedLocal,
        .call (.declaration (externalName `Array.set)),
        .localSet inlineSetResultLocal],
    .localGet inlineSetResultLocal] }

/-- Typed final-LCNF callers mirror upstream's inline exclusive update. Shared
and persistent arrays retain the complete copy-on-write helper. -/
def trustedCallSiteRewrites : Array ResidentCallSite.Rewrite := #[
  trustedSetCallSiteRewrite]

private partial def callSiteContains (needle : Instruction) :
    Instruction → Bool
  | .block _ body | .loop _ body => body.any (callSiteContains needle)
  | .ifElse thenBody elseBody =>
      thenBody.any (callSiteContains needle) ||
        elseBody.any (callSiteContains needle)
  | instruction => instruction == needle

#guard trustedSetCallSiteRewrite.locals.size == 8
#guard trustedSetCallSiteRewrite.body.any
  (callSiteContains (.i32Load .uint32 (u32 headerRefCountOffset)))
#guard trustedSetCallSiteRewrite.body.any
  (callSiteContains (.call (.declaration (externalName `Array.set))))

private def setBangOutOfBounds : List Instruction :=
  ResidentRelease.checkedDecrementLocal valueParam ++ [
  .localGet arrayParam,
  .ret]

private def checkSetBangBounds : List Instruction := [
  .localGet indexLocal,
  .localGet sizeLocal,
  .i32LtU,
  .ifElse [] setBangOutOfBounds]

private def decodeCheckedSetBangIndex : List Instruction := [
  .localGet indexParam,
  .call (.declaration ResidentNumeric.validateNaturalName),
  .localGet indexParam,
  .call (.declaration ResidentNumeric.naturalHighName),
  .localSet indexHighLocal,
  .localGet indexHighLocal,
  .i32Const .uint32 0,
  .i32Eq,
  .ifElse [
    .localGet indexParam,
    .call (.declaration ResidentNumeric.naturalLowName),
    .localSet indexLocal]
    setBangOutOfBounds] ++ checkSetBangBounds

/-- Upstream `lean_array_set` checks the scalar tag before unboxing a `Nat`.
Typed final-LCNF callers may skip the full resident-natural validator, but
`Array.set!` still treats heap naturals and scalar indices beyond the array as
out of bounds. -/
private def decodeTrustedSetBangIndex : List Instruction := [
  .localGet indexParam,
  .i32Const .uint32 1,
  .i32And,
  .ifElse
    (decodeTrustedNaturalIndex indexParam indexLocal ++ checkSetBangBounds)
    setBangOutOfBounds]

private def decodeSetBangIndexFor (validation : InputValidation) :
    List Instruction :=
  match validation with
  | .checked => decodeCheckedSetBangIndex
  | .trusted => decodeTrustedSetBangIndex

private def setBangFunctionFor (validation : InputValidation) : Function := {
  name := externalName `Array.set!
  params := #[(erasedParam, .erased), (arrayParam, .object),
    (indexParam, .tobject), (valueParam, .tobject)]
  results := #[.object]
  locals := setLocals.push (indexHighLocal, .uint32)
  body := validateArrayInput validation arrayParam ++
    captureInputAddress validation ++
    loadSize arrayParam ++ decodeSetBangIndexFor validation ++
    replaceAtDecodedIndexBody validation }

def setBangFunction : Function := setBangFunctionFor .checked

/-!
## Proof-visible trusted replacement helpers

These closed aliases expose the three production trusted replacement helpers
without making the validation modes or their constructors public.  The
resident linker continues to construct exactly the same function values; the
aliases and equations below are only a stable source-shape boundary for W6.
-/

/-- Closed executable body of the production trusted `Array.uset` helper. -/
def trustedUsetFunctionBody : List Instruction :=
  (usetFunctionFor .trusted .trusted).body

/-- Proof-visible value of the production trusted `Array.uset` helper. -/
def trustedUsetFunction : Function :=
  usetFunctionFor .trusted .trusted

@[simp] theorem trustedUsetFunction_name :
    trustedUsetFunction.name = externalName `Array.uset := rfl

@[simp] theorem trustedUsetFunction_signature :
    trustedUsetFunction.signature = {
      params := #[.erased, .object, .usize, .tobject, .erased]
      results := #[.object] } := by
  simp [trustedUsetFunction, Function.signature, usetFunctionFor]

theorem trustedUsetFunction_body :
    trustedUsetFunction.body = trustedUsetFunctionBody := rfl

/-- Closed executable body of the production trusted `Array.set` helper. -/
def trustedSetFunctionBody : List Instruction :=
  (setFunctionFor .trusted .trusted).body

/-- Proof-visible value of the production trusted `Array.set` helper. -/
def trustedSetFunction : Function :=
  setFunctionFor .trusted .trusted

@[simp] theorem trustedSetFunction_name :
    trustedSetFunction.name = externalName `Array.set := rfl

@[simp] theorem trustedSetFunction_signature :
    trustedSetFunction.signature = {
      params := #[.erased, .object, .tobject, .tobject, .erased]
      results := #[.object] } := by
  simp [trustedSetFunction, Function.signature, setFunctionFor]

theorem trustedSetFunction_body :
    trustedSetFunction.body = trustedSetFunctionBody := rfl

/-- Closed executable body of the production trusted `Array.set!` helper. -/
def trustedSetBangFunctionBody : List Instruction :=
  (setBangFunctionFor .trusted).body

/-- Proof-visible value of the production trusted `Array.set!` helper. -/
def trustedSetBangFunction : Function :=
  setBangFunctionFor .trusted

@[simp] theorem trustedSetBangFunction_name :
    trustedSetBangFunction.name = externalName `Array.set! := rfl

@[simp] theorem trustedSetBangFunction_signature :
    trustedSetBangFunction.signature = {
      params := #[.erased, .object, .tobject, .tobject]
      results := #[.object] } := by
  simp [trustedSetBangFunction, Function.signature, setBangFunctionFor]

theorem trustedSetBangFunction_body :
    trustedSetBangFunction.body = trustedSetBangFunctionBody := rfl

private def swapDecodedElementsFunction : Function := {
  name := swapElementsName
  params := #[(arrayParam, .uint32), (indexParam, .uint32),
    (index2Param, .uint32)]
  results := #[]
  locals := #[(countLocal, .uint32), (sourceCursorLocal, .uint32),
    (targetCursorLocal, .uint32), (elementLocal, .tobject),
    (element2Local, .tobject)]
  body :=
  elementAddressFor arrayParam indexParam sourceCursorLocal ++
  elementAddressFor arrayParam index2Param targetCursorLocal ++ [
    .localGet sourceCursorLocal,
    .i32Load .tobject 0,
    .localSet elementLocal,
    .localGet targetCursorLocal,
    .i32Load .tobject 0,
    .localSet element2Local] ++
    storeObjectWord sourceCursorLocal element2Local ++
    storeObjectWord targetCursorLocal elementLocal ++ [
    .ret] }

private def callSwapDecodedElements (array : FVarId) : List Instruction := [
  .localGet array,
  .localGet indexLocal,
  .localGet index2Local,
  .call (.declaration swapElementsName)]

private def swapFunctionFor (inputValidation : InputValidation)
    (proofIndexValidation : ProofIndexValidation) : Function := {
  name := externalName `Array.swap
  params := #[(erasedParam, .erased), (arrayParam, .object),
    (indexParam, .tobject), (index2Param, .tobject),
    (proofParam, .erased), (proof2Param, .erased)]
  results := #[.object]
  locals := #[(addressLocal, .uint32), (sizeLocal, .uint32),
    (inputAddressLocal, .uint32), (capacityLocal, .uint32),
    (exclusiveLocal, .uint32), (refCountLocal, .uint32),
    (indexLocal, .uint32), (index2Local, .uint32),
    (countLocal, .uint32), (sourceCursorLocal, .uint32),
    (targetCursorLocal, .uint32), (allocationBytesLocal, .uint32),
    (savedScratchLocal, .uint32), (objectResultLocal, .object),
    (elementLocal, .tobject), (element2Local, .tobject)]
  body := validateArrayInput inputValidation arrayParam ++
    captureInputAddress inputValidation ++
    loadSize arrayParam ++
    decodeProofNaturalIndex proofIndexValidation indexParam indexLocal ++
    decodeProofNaturalIndex proofIndexValidation index2Param index2Local ++
    loadCapacity arrayParam ++ selectExclusive inputValidation ++ [
    .localGet exclusiveLocal,
    .ifElse (callSwapDecodedElements inputAddressLocal ++ [
      .localGet arrayParam,
      .ret]) []] ++ allocationBytesBody ++ [
    .localGet allocationBytesLocal,
    .call (.declaration ResidentAllocator.allocateName),
    .localSet addressLocal] ++
    initializeHeader [.localGet sizeLocal] [.localGet capacityLocal] ++
    copyElementsBody true ++ consumeSharedArray ++
    callSwapDecodedElements addressLocal ++ retypeAddress }

def swapFunction : Function := swapFunctionFor .checked .checked

private def inputAddressPrefixDelta (checked trusted : Function) : Bool :=
  let validation := requireArray arrayParam
  checked.body.take validation.length == validation &&
    (checked.body.drop validation.length).take checkedInputAddress.length ==
        checkedInputAddress &&
    trusted.body.take trustedInputAddress.length == trustedInputAddress

#guard inputAddressPrefixDelta (pushFunctionFor .checked) (pushFunctionFor .trusted)
#guard inputAddressPrefixDelta (popFunctionFor .checked) (popFunctionFor .trusted)
#guard inputAddressPrefixDelta (setBangFunctionFor .checked)
  (setBangFunctionFor .trusted)

private def callsProofIndexDecoder : Instruction → Bool
  | .call (.declaration declaration) =>
      declaration == ResidentNumeric.validateNaturalName ||
        declaration == ResidentNumeric.naturalLowName ||
        declaration == ResidentNumeric.naturalHighName
  | _ => false

private def containsSequence (needle haystack : List Instruction) : Bool :=
  match haystack with
  | [] => needle.isEmpty
  | _ :: tail =>
      haystack.take needle.length == needle || containsSequence needle tail

termination_by haystack.length

#guard !containsSequence (selectExclusive .trusted)
  (replaceAtDecodedIndexBody .trusted)

private def naturalBoundsCheck (index : FVarId) : List Instruction := [
  .localGet index,
  .localGet sizeLocal,
  .i32LtU,
  .ifElse [] [.unreachable]]

private def usizeBoundsCheck : List Instruction := [
  .localGet indexParam,
  .localGet sizeLocal,
  .i64ExtendI32U .usize,
  .i64LtU,
  .ifElse [] [.unreachable]]

private def trustedProofIndexedFunctions : Array Function := #[
  getBorrowedFunctionFor .trusted .trusted,
  getFunctionFor .trusted .trusted,
  ugetBorrowedFunctionFor .trusted .trusted,
  ugetFunctionFor .trusted .trusted,
  usetFunctionFor .trusted .trusted,
  setFunctionFor .trusted .trusted,
  swapFunctionFor .trusted .trusted]

private def trustedMutationFunctions : Array Function := #[
  pushFunctionFor .trusted,
  popFunctionFor .trusted,
  usetFunctionFor .trusted .trusted,
  setFunctionFor .trusted .trusted,
  setBangFunctionFor .trusted,
  swapFunctionFor .trusted .trusted]

#guard captureInputAddress .checked == checkedInputAddress
#guard captureInputAddress .trusted == trustedInputAddress
#guard selectExclusive .checked == checkedSelectExclusive
#guard selectExclusive .trusted == trustedSelectExclusive
#guard trustedMutationFunctions.all fun function =>
  !containsSequence checkedInputAddress function.body &&
    !containsSequence checkedSelectExclusive function.body

#guard trustedProofIndexedFunctions.all fun function =>
  !function.body.any callsProofIndexDecoder &&
    !containsSequence (naturalBoundsCheck indexLocal) function.body &&
    !containsSequence (naturalBoundsCheck index2Local) function.body &&
    !containsSequence usizeBoundsCheck function.body

#guard (getBorrowedFunctionFor .trusted .trusted).body.take 4 ==
  decodeTrustedNaturalIndex indexParam indexLocal
#guard (getFunctionFor .trusted .trusted).body.take 4 ==
  decodeTrustedNaturalIndex indexParam indexLocal
#guard (ugetBorrowedFunctionFor .trusted .trusted).body.take 3 ==
  decodeProofUSizeIndex .trusted indexParam indexLocal
#guard (ugetFunctionFor .trusted .trusted).body.take 3 ==
  decodeProofUSizeIndex .trusted indexParam indexLocal

#guard (setBangFunctionFor .checked).body.any callsProofIndexDecoder
#guard !(setBangFunctionFor .trusted).body.any callsProofIndexDecoder
#guard containsSequence decodeCheckedSetBangIndex
  (setBangFunctionFor .checked).body
#guard containsSequence decodeTrustedSetBangIndex
  (setBangFunctionFor .trusted).body

private def fillElementsBody : List Instruction := [
  .localGet addressLocal,
  .i32Const .uint32 (u32 headerBytes),
  .i32Add,
  .localSet targetCursorLocal,
  .i32Const .uint32 0,
  .localSet countLocal,
  .loop copyLoopLabel ([
    .localGet countLocal,
    .localGet sizeLocal,
    .i32LtU,
    .ifElse (
      ([.localGet countLocal] ++ equalsConst .uint32 0 ++ [
        .ifElse [] [
          .localGet valueParam,
          .call (.declaration ResidentReferenceCount.incrementOnceName)]] ++
        storeObjectWord targetCursorLocal valueParam ++ [
        .localGet targetCursorLocal,
        .i32Const .uint32 (u32 target.semanticSlotBytes),
        .i32Add,
        .localSet targetCursorLocal,
        .localGet countLocal,
        .i32Const .uint32 1,
        .i32Add,
        .localSet countLocal,
        .br copyLoopLabel])) []])]

def replicateFunction : Function := {
  name := externalName `Array.replicate
  params := #[(erasedParam, .erased), (indexParam, .tobject),
    (valueParam, .tobject)]
  results := #[.object]
  locals := #[(addressLocal, .uint32), (sizeLocal, .uint32),
    (capacityLocal, .uint32), (indexLocal, .uint32),
    (countLocal, .uint32),
    (targetCursorLocal, .uint32), (allocationBytesLocal, .uint32),
    (savedScratchLocal, .uint32), (objectResultLocal, .object)]
  body := decodeIndex ++ [
    .localGet indexLocal,
    .localSet sizeLocal,
    .localGet indexLocal,
    .localSet capacityLocal] ++
    ResidentRelease.checkedDecrementLocal indexParam ++
    allocationBytesBody ++ [
    .localGet allocationBytesLocal,
    .call (.declaration ResidentAllocator.allocateName),
    .localSet addressLocal] ++
    initializeHeader [.localGet sizeLocal] [.localGet capacityLocal] ++
    fillElementsBody ++ [
    .localGet sizeLocal] ++ equalsConst .uint32 0 ++ [
    .ifElse (ResidentRelease.checkedDecrementLocal valueParam) []] ++
    retypeAddress }

private def functionsFor (validation : CallValidation) : Array Function := #[
  allocateEmptyFunction,
  allocateListConsFunction,
  swapDecodedElementsFunction,
  sizeFunctionFor validation.input,
  usizeFunctionFor validation.input,
  getBangFunction validation.input `Array.get!InternalBorrowed false,
  emptyWithCapacityFunction,
  mkEmptyFunction,
  getBorrowedFunctionFor validation.input validation.proofIndex,
  getFunctionFor validation.input validation.proofIndex,
  ugetBorrowedFunctionFor validation.input validation.proofIndex,
  ugetFunctionFor validation.input validation.proofIndex,
  pushFunctionFor validation.input,
  popFunctionFor validation.input,
  getBangFunction validation.input `Array.get!Internal true,
  usetFunctionFor validation.input validation.proofIndex,
  setFunctionFor validation.input validation.proofIndex,
  setBangFunctionFor validation.input,
  swapFunctionFor validation.input validation.proofIndex,
  replicateFunction,
  mkFunction,
  toListFunctionFor validation.input]

/-- Checked helper bodies used by the standalone/public resident Array surface. -/
def functions : Array Function := functionsFor checkedCalls

private partial def rewriteInstruction (declarations : Array Name) : Instruction → Instruction
  | .call (.declaration declaration) =>
      if declarations.contains declaration then
        .call (.declaration (externalName declaration))
      else .call (.declaration declaration)
  | .block label body => .block label (body.map (rewriteInstruction declarations))
  | .loop label body => .loop label (body.map (rewriteInstruction declarations))
  | .ifElse thenBody elseBody =>
      .ifElse (thenBody.map (rewriteInstruction declarations))
        (elseBody.map (rewriteInstruction declarations))
  | instruction => instruction

private def expectedSignature? (declaration : Name) : Option Signature :=
  if declaration == `Array.size then
    some { params := #[.erased, .object], results := #[.tagged] }
  else if declaration == `Array.usize then
    some { params := #[.erased, .object], results := #[.usize] }
  else if declaration == `Array.get!InternalBorrowed ||
      declaration == `Array.get!Internal then
    some {
      params := #[.erased, .tobject, .object, .tobject]
      results := #[.tobject] }
  else if declaration == `Array.emptyWithCapacity ||
      declaration == `Array.mkEmpty then
    some { params := #[.erased, .tobject], results := #[.object] }
  else if declaration == `Array.getInternalBorrowed then
    some {
      params := #[.erased, .object, .tobject, .erased]
      results := #[.tobject] }
  else if declaration == `Array.getInternal then
    some {
      params := #[.erased, .object, .tobject, .erased]
      results := #[.tobject] }
  else if declaration == `Array.ugetBorrowed then
    some {
      params := #[.erased, .object, .usize, .erased]
      results := #[.tobject] }
  else if declaration == `Array.uget then
    some {
      params := #[.erased, .object, .usize, .erased]
      results := #[.tobject] }
  else if declaration == `Array.uset then
    some {
      params := #[.erased, .object, .usize, .tobject, .erased]
      results := #[.object] }
  else if declaration == `Array.set then
    some {
      params := #[.erased, .object, .tobject, .tobject, .erased]
      results := #[.object] }
  else if declaration == `Array.set! then
    some {
      params := #[.erased, .object, .tobject, .tobject]
      results := #[.object] }
  else if declaration == `Array.swap then
    some {
      params := #[.erased, .object, .tobject, .tobject, .erased, .erased]
      results := #[.object] }
  else if declaration == `Array.replicate then
    some {
      params := #[.erased, .tobject, .tobject]
      results := #[.object] }
  else if declaration == `Array.mk then
    some { params := #[.erased, .tobject], results := #[.object] }
  else if declaration == `Array.toList then
    some { params := #[.erased, .object], results := #[.tobject] }
  else if declaration == `Array.push then
    some { params := #[.erased, .object, .tobject], results := #[.object] }
  else if declaration == `Array.pop then
    some { params := #[.erased, .object], results := #[.object] }
  else none

private def internalizeSelected (module : Module) (declarations : Array Name)
    (callValidation : CallValidation) (validate : Bool) :
    Except LinkError Module := do
  if validate then
    match Fir.Wasm.validateModule module with
    | .ok () => pure ()
    | .error error => throw (.invalidInput error)
  unless module.functions.any (·.name == ResidentAllocator.allocateName) &&
      module.functions.any (·.name == ResidentAllocator.recycleName) do
    throw .missingAllocator
  unless module.memory == some ResidentRuntime.residentMemory do
    throw .incompatibleMemory
  for name in #[ResidentNumeric.validateNaturalName,
      ResidentNumeric.naturalLowName, ResidentNumeric.naturalHighName] do
    unless module.functions.any (·.name == name) do
      throw (.missingNumericHelper name)
  for name in #[ResidentReferenceCount.incrementOnceName,
      ResidentRelease.decrementOnceName] do
    unless module.functions.any (·.name == name) do
      throw (.missingOwnershipHelper name)
  let needsEmptyAllocator := declarations.contains `Array.emptyWithCapacity ||
    declarations.contains `Array.mkEmpty || declarations.contains `Array.mk
  let needsListConsAllocator := declarations.contains `Array.toList
  let needsSwap := declarations.contains `Array.swap
  let selectedHelperNames := declarations.map externalName
  let selectedHelperNames := if needsEmptyAllocator then
    #[allocateEmptyName] ++ selectedHelperNames
  else selectedHelperNames
  let selectedHelperNames := if needsListConsAllocator then
    #[allocateListConsName] ++ selectedHelperNames
  else selectedHelperNames
  let selectedHelperNames := if needsSwap then
    selectedHelperNames.push swapElementsName
  else selectedHelperNames
  for name in selectedHelperNames do
    if module.imports.any (·.declaration? == some name) ||
        module.functions.any (·.name == name) || module.exports.contains name then
      throw (.reservedDeclaration name)
  for declaration in declarations do
    let imports := module.imports.filter (·.declaration? == some declaration)
    unless imports.size == 1 do
      throw (.missingExternal declaration)
    let some signature := expectedSignature? declaration |
      throw (.incompatibleExternal declaration)
    unless imports[0]!.signature == signature do
      throw (.incompatibleExternal declaration)
  let callerRewrites := match callValidation.input,
      callValidation.proofIndex with
    | .trusted, .trusted => trustedCallSiteRewrites.filter fun rewrite =>
        match rewrite.target with
        | .declaration declaration => declarations.contains declaration
        | .runtime _ => false
    | _, _ => #[]
  let callerRewritten ←
    ResidentCallSite.rewriteModuleFunctions callerRewrites module
      |>.mapError LinkError.callSite
  let linkedFunctions := callerRewritten.map fun function =>
    { function with body := function.body.map (rewriteInstruction declarations) }
  let selectedFunctions := (functionsFor callValidation).filter fun function =>
    selectedHelperNames.contains function.name
  let linkedFunctions := linkedFunctions ++ selectedFunctions
  let imports := module.imports.filter fun import_ =>
    match import_.declaration? with
    | some declaration => !declarations.contains declaration
    | none => true
  let result : Module := {
    module with
    functions := linkedFunctions
    imports
    exports := selectedHelperNames.foldl Fir.Wasm.addUnique module.exports
    runtimeOperations := Fir.Wasm.collectRuntimeOps linkedFunctions }
  if validate then
    match Fir.Wasm.validateModule result with
    | .ok () => return result
    | .error error => throw (.invalidOutput error)
  else return result

/-- Internalize the complete historical array frontier, rejecting omissions. -/
def internalize (module : Module) (validate : Bool := true) : Except LinkError Module :=
  internalizeSelected module externalDeclarations checkedCalls validate

/--
Internalize the strict Array frontier for calls originating in typed final
LCNF. This mirrors Lean's native runtime: the operation trusts the Array
representation invariant, while retaining bounds, ownership, uniqueness, and
copy-on-write behavior. Raw/public callers use `internalize` instead.
-/
def internalizeTrusted (module : Module) (validate : Bool := true) :
    Except LinkError Module :=
  internalizeSelected module externalDeclarations trustedCalls validate

/--
Internalize exactly the array operations imported by a source closure.  This
keeps narrowly linked resident packages independent of unrelated array APIs
while preserving the same fail-closed signature checks as `internalize`.
-/
def internalizeAvailable (module : Module) (validate : Bool := true) : Except LinkError Module :=
  let declarations := availableExternalDeclarations.filter fun declaration =>
    module.imports.any (·.declaration? == some declaration)
  internalizeSelected module declarations checkedCalls validate

/--
Internalize exactly the Array operations imported by a typed closed
application, consuming the resident Array invariant rather than repeating the
raw-address validator at every compiled call.
-/
def internalizeAvailableTrusted (module : Module) (validate : Bool := true) :
    Except LinkError Module :=
  let declarations := availableExternalDeclarations.filter fun declaration =>
    module.imports.any (·.declaration? == some declaration)
  internalizeSelected module declarations trustedCalls validate

private def exampleDeclarations : Array Name :=
  #[`Array.emptyWithCapacity, `Array.push, `Array.ugetBorrowed, `Array.uget,
    `Array.get!InternalBorrowed, `Array.get!Internal,
    `Array.uset, `Array.replicate, `Array.pop,
    `Array.getInternalBorrowed, `Array.getInternal, `Array.set,
    `Array.set!, `Array.swap, `Array.mk, `Array.toList]

private def exampleReleaseOperation : RuntimeOp := .dec 1 true none

def exampleReleaseName : Name := `resident_array_release

private def exampleReleaseFunction : Function := {
  name := exampleReleaseName
  params := #[(arrayParam, .tobject)]
  results := #[]
  locals := #[]
  body := [
    .localGet arrayParam,
    .call (.runtime exampleReleaseOperation),
    .ret] }

def setCallerName : Name := `fir_example_Array_setCaller

private def setCallerFunction : Function := {
  name := setCallerName
  params := #[(erasedParam, .erased), (arrayParam, .object),
    (indexParam, .tobject), (valueParam, .tobject), (proofParam, .erased)]
  results := #[.object]
  locals := #[]
  body := [
    .localGet erasedParam,
    .localGet arrayParam,
    .localGet indexParam,
    .localGet valueParam,
    .localGet proofParam,
    .call (.declaration `Array.set),
    .ret] }

private def exampleExternalTypes (declaration : Name) : ExternalTypes :=
  let erased := LCNF.ImpureType.erased
  let object := LCNF.ImpureType.object
  let tobject := LCNF.ImpureType.tobject
  let usize := LCNF.ImpureType.usize
  if declaration == `Array.emptyWithCapacity then
    { params := #[erased, tobject], result := object }
  else if declaration == `Array.push then
    { params := #[erased, object, tobject], result := object }
  else if declaration == `Array.ugetBorrowed || declaration == `Array.uget then
    { params := #[erased, object, usize, erased], result := tobject }
  else if declaration == `Array.uset then
    { params := #[erased, object, usize, tobject, erased], result := object }
  else if declaration == `Array.get!InternalBorrowed ||
      declaration == `Array.get!Internal then
    { params := #[erased, tobject, object, tobject], result := tobject }
  else if declaration == `Array.getInternalBorrowed ||
      declaration == `Array.getInternal then
    { params := #[erased, object, tobject, erased], result := tobject }
  else if declaration == `Array.set then
    { params := #[erased, object, tobject, tobject, erased], result := object }
  else if declaration == `Array.set! then
    { params := #[erased, object, tobject, tobject], result := object }
  else if declaration == `Array.swap then
    { params := #[erased, object, tobject, tobject, erased, erased],
      result := object }
  else if declaration == `Array.pop then
    { params := #[erased, object], result := object }
  else if declaration == `Array.mk then
    { params := #[erased, tobject], result := object }
  else if declaration == `Array.toList then
    { params := #[erased, object], result := tobject }
  else
    { params := #[erased, tobject, tobject], result := object }

private def exampleExternalImport (declaration : Name) : Import := {
  key := .external declaration
  moduleName := "lean.extern"
  itemName := declaration.toString
  signature := (expectedSignature? declaration).get!
  externalTypes? := some (exampleExternalTypes declaration) }

/-- Common closed generation-only probe input for the resident Array surface. -/
private def residentExampleInput : Except String Module := do
  let numeric ← ResidentNumeric.residentExampleModule
  let numeric : Module := {
    numeric with
    imports := numeric.imports.push <|
      Fir.Wasm.runtimeImport numeric.imports.size exampleReleaseOperation
    functions := numeric.functions.push exampleReleaseFunction
    exports := Fir.Wasm.addUnique numeric.exports exampleReleaseName
    runtimeOperations := numeric.runtimeOperations.push exampleReleaseOperation }
  let references ← ResidentReferenceCount.internalizeIncrements numeric
    |>.mapError fun error => s!"array reference counts: {repr error}"
  let releases ← ResidentRelease.internalizeReleases references
    |>.mapError fun error => s!"array releases: {repr error}"
  let module : Module := {
    releases with
    imports := releases.imports ++ exampleDeclarations.map exampleExternalImport
    functions := releases.functions.push setCallerFunction
    exports := Fir.Wasm.addUnique releases.exports setCallerName }
  pure module

/-- Closed checked/public probe for the resident Array surface. -/
def residentExampleModule : Except String Module := do
  let module ← residentExampleInput
  internalizeSelected module exampleDeclarations checkedCalls true
    |>.mapError fun error => s!"array: {repr error}"

/-- Closed typed-application probe for the upstream-trusted Array surface. -/
def residentTrustedExampleModule : Except String Module := do
  let module ← residentExampleInput
  internalizeSelected module exampleDeclarations trustedCalls true
    |>.mapError fun error => s!"trusted array: {repr error}"

def manifest : Json :=
  Json.mkObj [
    ("entries", Json.arr <| exampleDeclarations.map fun declaration =>
      Json.mkObj [
        ("sourceEntry", declaration.toString),
        ("entry", externalName declaration |>.toString)]),
    ("releaseEntry", exampleReleaseName.toString),
    ("imports", Json.arr #[]),
    ("status", "generation-ready; W6 array contract proofs pending")]

#guard match residentExampleModule with
  | .ok module =>
      module.imports.isEmpty &&
      module.runtimeOperations.isEmpty &&
      exampleDeclarations.all fun declaration =>
        module.exports.contains (externalName declaration) &&
      module.memory == some ResidentRuntime.residentMemory &&
      (Fir.Wasm.validateModule module |>.isOk) &&
      (Fir.Wasm.Emit.encode module |>.isOk)
  | .error _ => false

#guard match residentTrustedExampleModule with
  | .ok module =>
      module.imports.isEmpty &&
      module.runtimeOperations.isEmpty &&
      exampleDeclarations.all fun declaration =>
        module.exports.contains (externalName declaration) &&
      module.memory == some ResidentRuntime.residentMemory &&
      (Fir.Wasm.validateModule module |>.isOk) &&
      (Fir.Wasm.Emit.encode module |>.isOk)
  | .error _ => false

#guard match residentTrustedExampleModule with
  | .ok module =>
      match module.functions.find? (·.name == setCallerName) with
      | some caller => caller.locals.size == 8 &&
          caller.body != setCallerFunction.body
      | none => false
  | .error _ => false

end Fir.Wasm.Emit.ResidentArray
