import Fir.Wasm.Emit.ResidentAllocator
import Fir.Wasm.Emit.ResidentContainerLayout

namespace Fir.Wasm.Emit.ResidentRelease

open Fir.Wasm
open Fir.Wasm.Concrete
open Lean

private def objectParam : FVarId := ⟨`object⟩
private def checkParam : FVarId := ⟨`check⟩
private def addressLocal : FVarId := ⟨`address⟩
private def kindLocal : FVarId := ⟨`kind⟩
private def countLocal : FVarId := ⟨`count⟩
private def captureCountLocal : FVarId := ⟨`captureCount⟩
private def descriptorLocal : FVarId := ⟨`descriptor⟩
private def refCountLocal : FVarId := ⟨`refCount⟩
private def flagsLocal : FVarId := ⟨`flags⟩
private def markerLocal : FVarId := ⟨`marker⟩
private def arrayCursorLocal : FVarId := ⟨`arrayCursor⟩
private def arrayIndexLocal : FVarId := ⟨`arrayIndex⟩
private def arrayReleaseLoop : FVarId := ⟨`arrayReleaseLoop⟩

inductive LinkError where
  | invalidInput (error : SymbolicError)
  | reservedDeclaration (name : Name)
  | unsupportedOperation
  | amountOverflow (amount : Nat)
  | descriptorOverflow (count : Nat)
  | incompatibleMemory
  | invalidOutput (error : SymbolicError)
  deriving Inhabited, Repr

def u32 (value : Nat) : UInt32 := UInt32.ofNat value

def checkedWord (value : Nat) : Except LinkError UInt32 :=
  if value < UInt32.size then
    pure (u32 value)
  else
    throw (.amountOverflow value)

def isRelease : RuntimeOp → Bool
  | .dec .. | .delete => true
  | _ => false

def releaseName (ordinal : Nat) : Name :=
  Name.mkSimple s!"fir_release_{ordinal}"

def releaseHeaderName : Name := `fir_release_header
def decrementOnceName : Name := `fir_dec_once

/--
The compiler-produced `prettyM` graph has at most five constructor object
fields. The resident recursive helper accepts a much wider 32-field frontier
and traps before reading any object beyond it. This is a generation boundary,
not a replacement for a future unbounded release loop instruction.
-/
def constructorFieldLimit : Nat := 32

/-!
The definitions in this section form the reduction-visible proof surface for
the exact production decrement body.  They are compositional views of the
actual emitter implementation, not an independent certificate or alternate
body generator.  `decrementOnceFunction` consumes `decrementOnceBody`, which
in turn consumes these exact staged builders.
-/
@[expose] section

def equalsConst (kind : AbiKind) (value : UInt32) :
    List Instruction :=
  [.i32Const kind value, .i32Eq]

def checkedNoop : List Instruction :=
  [.localGet checkParam, .ifElse [.ret] [.unreachable]]

def releaseHeaderBody (_recycle : Bool := false) : List Instruction := [
    .localGet addressLocal,
    .i32Const .uint32 ObjectKind.freed.code,
    .i32Store .uint32 (u32 headerKindOffset),
    .localGet addressLocal,
    .i32Const .uint32 0,
    .i32Store .uint32 (u32 headerFlagsOffset),
    .localGet addressLocal,
    .i32Const .uint32 0,
    .i32Store .uint32 (u32 headerRefCountOffset),
    .localGet addressLocal,
    .i32Const .uint32 0,
    .i32Store .uint32 (u32 headerAux0Offset),
    .localGet addressLocal,
    .i32Const .uint32 0,
    .i32Store .uint32 (u32 headerAux1Offset),
    .localGet addressLocal,
    .i32Const .uint32 0,
    .i32Store .uint32 (u32 headerAux2Offset),
    .localGet addressLocal,
    .i32Const .uint32 0,
    .i32Store .uint32 (u32 headerAux3Offset),
    .ret]

/--
The standalone header-release helper used when no resident allocator has been
installed. This definition remains public for the existing concrete proof.
-/
def releaseHeaderFunction : Function := {
  name := releaseHeaderName
  params := #[(addressLocal, .uint32)]
  results := #[]
  locals := #[]
  body := releaseHeaderBody false }

/--
Compatibility shape for the allocator-aware path. Recycling happens only
after recursive child descent, because the allocator-private link occupies an
ignored dead payload word that may still contain an owned child before descent.
-/
def recyclingReleaseHeaderFunction : Function := {
  name := releaseHeaderName
  params := #[(addressLocal, .uint32)]
  results := #[]
  locals := #[]
  body := releaseHeaderBody true }

/-- Complete one last-reference release after every owned payload lane has
been consumed. The standalone proof path retains its original return; the
allocator-aware production path offers the now-ignored payload to the private
reuse index first. -/
def finishReleaseBody (recycle : Bool := false) : List Instruction :=
  (if recycle then [
    .localGet addressLocal,
    .call (.declaration ResidentAllocator.recycleName)]
  else []) ++ [.ret]

def releaseChild (index : Nat) : List Instruction :=
  [.localGet addressLocal,
    .i32Load .tobject (u32 (headerBytes + target.semanticSlotBytes * index)),
    .i32Const .uint32 1,
    .call (.declaration decrementOnceName)]

def releaseConstructorFields : List Instruction :=
  (List.range constructorFieldLimit).flatMap fun index =>
    [.i32Const .uint32 (u32 index),
      .localGet countLocal,
      .i32LtU,
      .ifElse (releaseChild index) []]

def constructorReleaseBody (recycle : Bool := false) : List Instruction :=
  [.i32Const .uint32 (u32 constructorFieldLimit),
    .localGet countLocal,
    .i32LtU,
    .ifElse
      [.unreachable]
      (releaseConstructorFields ++ finishReleaseBody recycle)]

def arrayReleaseBody (recycle : Bool := false) : List Instruction := [
  .localGet addressLocal,
  .i32Const .uint32 (u32 headerBytes),
  .i32Add,
  .localSet arrayCursorLocal,
  .i32Const .uint32 0,
  .localSet arrayIndexLocal,
  .loop arrayReleaseLoop [
    .localGet arrayIndexLocal,
    .localGet countLocal,
    .i32LtU,
    .ifElse [
      .localGet arrayCursorLocal,
      .i32Load .tobject 0,
      .i32Const .uint32 1,
      .call (.declaration decrementOnceName),
      .localGet arrayCursorLocal,
      .i32Const .uint32 (u32 target.semanticSlotBytes),
      .i32Add,
      .localSet arrayCursorLocal,
      .localGet arrayIndexLocal,
      .i32Const .uint32 1,
      .i32Add,
      .localSet arrayIndexLocal,
      .br arrayReleaseLoop] []]] ++ finishReleaseBody recycle

def opaqueReleaseBody (recycle : Bool := false) : List Instruction :=
  [.localGet markerLocal] ++
  equalsConst .uint32 ResidentContainerLayout.arrayMarker ++
  [.ifElse (arrayReleaseBody recycle) (finishReleaseBody recycle)]

def descriptorOwnedFields (descriptor : Array AbiKind) :
    List Instruction :=
  descriptor.toList.zipIdx.flatMap fun (kind, index) =>
    if kind.isObjectField then releaseChild index else []

def descriptorReleaseBody (recycle : Bool := false) :
    List (Array AbiKind) → Nat → Except LinkError (List Instruction)
  | [], _ => pure [.unreachable]
  | descriptor :: descriptors, index => do
    let descriptorIndex ← checkedWord index
    let captureCount ← checkedWord descriptor.size
    let rest ← descriptorReleaseBody recycle descriptors (index + 1)
    return (
      [.localGet descriptorLocal] ++
      equalsConst .uint32 descriptorIndex ++
      [.ifElse
        ([.localGet captureCountLocal] ++
          equalsConst .uint32 captureCount ++
          [.ifElse
            (descriptorOwnedFields descriptor ++ finishReleaseBody recycle)
            [.unreachable]])
        rest])

def ownedReleaseBody (descriptors : Array (Array AbiKind))
    (recycle : Bool := false) :
    Except LinkError (List Instruction) := do
  let closureBody ← descriptorReleaseBody recycle descriptors.toList 0
  return (
    [.localGet kindLocal] ++
    equalsConst .uint32 ObjectKind.constructor.code ++
    [.ifElse
      (constructorReleaseBody recycle)
      ([.localGet kindLocal] ++
        equalsConst .uint32 ObjectKind.closure.code ++
        [.ifElse closureBody
          ([.localGet kindLocal] ++
            equalsConst .uint32 ObjectKind.opaque.code ++
            [.ifElse (opaqueReleaseBody recycle)
              (finishReleaseBody recycle)])])])

def decrementAboveOneBody : List Instruction :=
  [.localGet addressLocal,
    .localGet refCountLocal,
    .i32Const .uint32 1,
    .i32Sub,
    .i32Store .uint32 (u32 headerRefCountOffset),
    .ret]

/-
Loading the terminal header word is the cheapest exact preservation of the old
full-header memory-boundary check. It also caches the closure descriptor for
the cold last-reference path. The ordinary shared-reference path deliberately
does not interpret object kind or auxiliary metadata.
-/
def probeCompleteHeader : List Instruction :=
  [.localGet addressLocal,
    .i32Load .uint32 (u32 headerAux3Offset),
    .localSet descriptorLocal]

def lastReferenceReleaseBody
    (descriptors : Array (Array AbiKind)) (recycle : Bool := false) :
    Except LinkError (List Instruction) := do
  let owned ← ownedReleaseBody descriptors recycle
  return (
    [.localGet addressLocal,
      .i32Load .uint32 (u32 headerKindOffset),
      .localSet kindLocal,
      .localGet addressLocal,
      .i32Load .uint32 (u32 headerAux0Offset),
      .localSet markerLocal,
      .localGet addressLocal,
      .i32Load .uint32 (u32 headerAux1Offset),
      .localSet countLocal,
      .localGet addressLocal,
      .i32Load .uint32 (u32 headerAux2Offset),
      .localSet captureCountLocal,
      .localGet addressLocal,
      .call (.declaration releaseHeaderName)] ++ owned)

def ordinaryReleaseBody
    (descriptors : Array (Array AbiKind)) (recycle : Bool := false) :
    Except LinkError (List Instruction) := do
  let lastReference ← lastReferenceReleaseBody descriptors recycle
  return (
    [.localGet addressLocal,
      .i32Load .uint32 (u32 headerRefCountOffset),
      .localSet refCountLocal,
      .localGet refCountLocal] ++
    equalsConst .uint32 0 ++
    [.ifElse
      [.unreachable]
      ([.i32Const .uint32 1,
        .localGet refCountLocal,
        .i32LtU,
        .ifElse
          decrementAboveOneBody
          lastReference])])

def persistentReleaseBody : List Instruction :=
  [.localGet addressLocal,
    .i32Load .uint32 (u32 headerKindOffset),
    .localSet kindLocal,
    .localGet addressLocal,
    .i32Load .uint32 (u32 headerAux0Offset),
    .localSet markerLocal,
    .localGet kindLocal] ++
  equalsConst .uint32 ObjectKind.natural.code ++
  [.ifElse
    ([.localGet addressLocal,
      .i32Load .uint32 (u32 headerAux0Offset)] ++
      equalsConst .uint32 promotedTagMarker ++
      [.ifElse checkedNoop [.ret]])
    [.ret]]

def liveReleaseBody
    (descriptors : Array (Array AbiKind)) (recycle : Bool := false) :
    Except LinkError (List Instruction) := do
  let ordinary ← ordinaryReleaseBody descriptors recycle
  return (
    probeCompleteHeader ++
    [.localGet flagsLocal,
      .i32Const .uint32 persistentFlag,
      .i32And] ++
    equalsConst .uint32 persistentFlag ++
    [.ifElse persistentReleaseBody ordinary])

def alignedReleaseBody
    (descriptors : Array (Array AbiKind)) (recycle : Bool := false) :
    Except LinkError (List Instruction) := do
  let live ← liveReleaseBody descriptors recycle
  return (
    [.localGet objectParam,
      .i32Const .uint32 0,
      .i32Add,
      .localSet addressLocal,
      .localGet addressLocal,
      .i32Load .uint32 (u32 headerFlagsOffset),
      .localSet flagsLocal,
      .localGet flagsLocal,
      .i32Const .uint32 liveFlag,
      .i32And] ++
    equalsConst .uint32 liveFlag ++
    [.ifElse live [.unreachable]])

/--
Build the exact instruction body installed as `fir_dec_once`.  This is the
public proof surface for production decrement control flow: it is assembled by
the same staged builders as the executable emitter and remains parameterized by
the supplied closure-descriptor table.
-/
def decrementOnceBody
    (descriptors : Array (Array AbiKind)) (recycle : Bool := false) :
    Except LinkError (List Instruction) := do
  let aligned ← alignedReleaseBody descriptors recycle
  return [.localGet objectParam,
      .i32Const .uint32 1,
      .i32And,
      .ifElse
        checkedNoop
        ([.localGet objectParam] ++
          equalsConst .tobject 0 ++
          [.ifElse
            checkedNoop
            ([.localGet objectParam,
              .i32Const .uint32 (u32 (target.heapAlignment - 1)),
              .i32And] ++
              equalsConst .uint32 0 ++
              [.ifElse aligned [.unreachable]])])]

/--
Build the production nonrecursive decrement helper installed by
`internalizeReleases`. This definition is public so the concrete-runtime proof
can unfold the exact generated function rather than duplicate its body.
-/
def decrementOnceFunction
    (descriptors : Array (Array AbiKind)) (recycle : Bool := false) :
    Except LinkError Function := do
  if UInt32.size ≤ descriptors.size then
    throw (.descriptorOverflow descriptors.size)
  let body ← decrementOnceBody descriptors recycle
  return {
    name := decrementOnceName
    params := #[(objectParam, .tobject), (checkParam, .uint32)]
    results := #[]
    locals := #[
      (addressLocal, .uint32),
      (kindLocal, .uint32),
      (countLocal, .uint32),
      (captureCountLocal, .uint32),
      (descriptorLocal, .uint32),
      (refCountLocal, .uint32),
      (flagsLocal, .uint32),
      (markerLocal, .uint32),
      (arrayCursorLocal, .uint32),
      (arrayIndexLocal, .uint32)]
    body }

/--
Successful production generation uses exactly `decrementOnceBody`; no caller
supplies or certifies an independent instruction list.
-/
theorem decrementOnceFunction_body_of_ok
    {descriptors : Array (Array AbiKind)} {function : Function}
    (generated : decrementOnceFunction descriptors = .ok function) :
    ∃ body, decrementOnceBody descriptors = .ok body ∧
      function.body = body := by
  unfold decrementOnceFunction at generated
  split at generated
  · cases generated
  · cases bodyGenerated : decrementOnceBody descriptors with
    | error error =>
      rw [bodyGenerated] at generated
      cases generated
    | ok body =>
      rw [bodyGenerated] at generated
      exact ⟨body, rfl,
        (congrArg Function.body (Except.ok.inj generated)).symm⟩

end

private def decrementOnceCall (check : Bool) : List Instruction :=
  [.localGet objectParam,
    .i32Const .uint32 (if check then 1 else 0),
    .call (.declaration decrementOnceName)]

/-
Lean's native `lean_dec` keeps the scalar test in the compiled caller and only
enters the cold recursive release path for a heap reference.  Checked FIR
decrements also accept the erased zero sentinel, so test it beside tagged
immediates before calling `fir_dec_once`. The helper deliberately retains its
own checks: recursive release and the public helper boundary still enter it
directly, and malformed heap references must keep trapping there.
-/
private def checkedDecrementLocalCalls
    (value : FVarId) (calls : List Instruction) :
    List Instruction :=
  [.localGet value,
    .i32Const .uint32 1,
    .i32And,
    .ifElse []
      ([.localGet value] ++
        equalsConst .tobject 0 ++
        [.ifElse [] calls])]

/--
Emit upstream-shaped `lean_dec` control flow for a checked resident value.
Tagged immediates and the erased-zero sentinel stay in the caller; only heap
references enter the stable `fir_dec_once` helper boundary.
-/
def checkedDecrementLocal (value : FVarId) : List Instruction :=
  checkedDecrementLocalCalls value
    [.localGet value,
      .i32Const .uint32 1,
      .call (.declaration decrementOnceName)]

/-
Preserve the object-family precision already present on symbolic function
locals before release operations are collapsed into shared `tobject`
wrappers. A checked decrement of a definite tagged immediate is a no-op. A
definite heap object can use the existing unchecked operation; only a genuine
`tobject` keeps the checked wrapper.

Production lowering emits the release operand as the immediately preceding
`localGet`. Other stack shapes remain unchanged and retain the complete
runtime operation rather than being guessed from physical `i32` shape.
-/
private partial def specializeCheckedDecrementInstructions
    (locals : LocalKinds) : List Instruction → List Instruction
  | [] => []
  | .localGet value ::
      .call (.runtime (.dec amount true objectFields?)) :: rest =>
      match findLocalKind? locals value with
      | some .tagged => specializeCheckedDecrementInstructions locals rest
      | some .object =>
          .localGet value ::
            .call (.runtime (.dec amount false objectFields?)) ::
              specializeCheckedDecrementInstructions locals rest
      | _ =>
          .localGet value ::
            .call (.runtime (.dec amount true objectFields?)) ::
              specializeCheckedDecrementInstructions locals rest
  | instruction :: rest =>
      let instruction := match instruction with
        | .block label body =>
            .block label (specializeCheckedDecrementInstructions locals body)
        | .loop label body =>
            .loop label (specializeCheckedDecrementInstructions locals body)
        | .ifElse thenBody elseBody =>
            .ifElse
              (specializeCheckedDecrementInstructions locals thenBody)
              (specializeCheckedDecrementInstructions locals elseBody)
        | instruction => instruction
      instruction :: specializeCheckedDecrementInstructions locals rest

/-- Specialize only compiler-shaped checked decrement sites using their exact
symbolic local kind. This is deliberately independent of declaration names and
physical Wasm indices. -/
def specializeCheckedDecrementFunction (function : Function) : Function :=
  { function with
    body := specializeCheckedDecrementInstructions
      (function.params.toList ++ function.locals.toList) function.body }

/-- Specialize checked decrement operands across a module and refresh the
runtime frontier immediately. Resident planning must call this before it
inventories operations: specialization can select an unchecked decrement that
was not present in the original module. -/
def specializeCheckedDecrements (module : Module) : Module :=
  let functions := module.functions.map specializeCheckedDecrementFunction
  let runtimeOperations := Fir.Wasm.collectRuntimeOps functions
  let externalImports := module.imports.filter (·.operation?.isNone)
  { module with
    functions
    imports := runtimeOperations.mapIdx Fir.Wasm.runtimeImport ++ externalImports
    runtimeOperations }

private def checkedDecrementCalls (calls : List Instruction) :
    List Instruction :=
  checkedDecrementLocalCalls objectParam calls

private def decrementWrapper (ordinal amount : Nat) (check : Bool) :
    Except LinkError Function := do
  let _ ← checkedWord amount
  let calls := (List.replicate amount (decrementOnceCall check)).flatten
  let body := if amount == 0 then [] else if check then
    checkedDecrementCalls calls
  else calls
  return {
    name := releaseName ordinal
    params := #[(objectParam, .tobject)]
    results := #[]
    locals := #[]
    body := body ++ [.ret] }

private def deleteReleasedBody (recycle : Bool := false) : List Instruction :=
  [.localGet addressLocal,
    .call (.declaration releaseHeaderName)] ++ finishReleaseBody recycle

private def deleteLiveBody (recycle : Bool := false) : List Instruction :=
  [.localGet addressLocal,
    .i32Load .uint32 (u32 headerKindOffset)] ++
  equalsConst .uint32 ObjectKind.natural.code ++
  [.ifElse
    ([.localGet addressLocal,
      .i32Load .uint32 (u32 headerFlagsOffset),
      .i32Const .uint32 persistentFlag,
      .i32And] ++
      equalsConst .uint32 persistentFlag ++
      [.ifElse
        ([.localGet addressLocal,
          .i32Load .uint32 (u32 headerAux0Offset)] ++
          equalsConst .uint32 promotedTagMarker ++
          [.ifElse [.unreachable] (deleteReleasedBody recycle)])
        (deleteReleasedBody recycle)])
    (deleteReleasedBody recycle)]

private def deleteAlignedBody (recycle : Bool := false) : List Instruction :=
  [.localGet objectParam,
    .i32Const .uint32 0,
    .i32Add,
    .localSet addressLocal,
    .localGet addressLocal,
    .i32Load .uint32 (u32 headerFlagsOffset),
    .i32Const .uint32 liveFlag,
  .i32And] ++
  equalsConst .uint32 liveFlag ++
  [.ifElse (deleteLiveBody recycle) [.unreachable]]

private def deleteWrapper (ordinal : Nat) (recycle : Bool := false) : Function := {
  name := releaseName ordinal
  params := #[(objectParam, .object)]
  results := #[]
  locals := #[(addressLocal, .uint32)]
  body :=
    [.localGet objectParam] ++
    equalsConst .object 0 ++
    [.ifElse
      [.ret]
      ([.localGet objectParam,
        .i32Const .uint32 1,
        .i32And,
        .ifElse
          [.unreachable]
          ([.localGet objectParam,
            .i32Const .uint32 (u32 (target.heapAlignment - 1)),
            .i32And] ++
            equalsConst .uint32 0 ++
            [.ifElse (deleteAlignedBody recycle) [.unreachable]])])] }

private def operationFunction (ordinal : Nat) (operation : RuntimeOp)
    (recycle : Bool := false) :
    Except LinkError Function :=
  match operation with
  | .dec amount check _ => decrementWrapper ordinal amount check
  | .delete => pure (deleteWrapper ordinal recycle)
  | _ => throw .unsupportedOperation

private partial def rewriteInstruction
    (rewrites : List (RuntimeOp × Name)) : Instruction → Instruction
  | .call (.runtime candidate) =>
      match rewrites.find? (·.1 == candidate) with
      | some (_, name) => .call (.declaration name)
      | none => .call (.runtime candidate)
  | .block label body =>
      .block label (body.map (rewriteInstruction rewrites))
  | .loop label body =>
      .loop label (body.map (rewriteInstruction rewrites))
  | .ifElse thenBody elseBody =>
      .ifElse
        (thenBody.map (rewriteInstruction rewrites))
        (elseBody.map (rewriteInstruction rewrites))
  | instruction => instruction

private def rewriteFunction (rewrites : List (RuntimeOp × Name))
    (function : Function) : Function :=
  { function with body := function.body.map (rewriteInstruction rewrites) }

private def reserved (module : Module) (name : Name) : Bool :=
  module.imports.any (·.declaration? == some name) ||
    module.functions.any (·.name == name) ||
    module.exports.contains name

/--
Internalize recursive `dec` and nonrecursive `delete`. Parent headers are
marked freed before descending into constructor fields or statically described
closure captures, so cycles fail on a dead header rather than recurring.
-/
def internalizeReleases (module : Module) (validate : Bool := true) :
    Except LinkError Module := do
  if validate then
    match Fir.Wasm.validateModule module with
    | .ok () => pure ()
    | .error error => throw (.invalidInput error)
  unless module.memory == some ResidentRuntime.residentMemory do
    throw .incompatibleMemory
  let specialized := specializeCheckedDecrements module
  let specializedFunctions := specialized.functions
  let encounteredOperations :=
    specialized.runtimeOperations.filter isRelease
  /-
  Preserve the input module's reviewed first-use order for surviving release
  operations. Specialization may introduce an unchecked variant that was not
  previously present; append only such genuinely new operations in their new
  first-use order.
  -/
  let operations := encounteredOperations.foldl
    (init := specialized.runtimeOperations.filter fun operation =>
      isRelease operation && encounteredOperations.contains operation)
    Fir.Wasm.addUnique
  let rewrites := operations.toList.zipIdx.map fun (operation, ordinal) =>
    (operation, releaseName ordinal)
  let reservedNames :=
    releaseHeaderName :: decrementOnceName :: rewrites.map (·.2)
  if let some name := reservedNames.find? (reserved module) then
    throw (.reservedDeclaration name)
  let recycle := specialized.functions.any
    (·.name == ResidentAllocator.recycleName)
  let decrementOnce ← decrementOnceFunction module.closureDescriptors recycle
  let wrappers ← operations.toList.zipIdx.mapM fun (operation, ordinal) =>
    operationFunction ordinal operation recycle
  let releaseHeader := releaseHeaderFunction
  let functions :=
    (specializedFunctions.map (rewriteFunction rewrites)) ++
      #[releaseHeader, decrementOnce] ++ wrappers.toArray
  let runtimeOperations := Fir.Wasm.collectRuntimeOps functions
  let externalImports := specialized.imports.filter (·.operation?.isNone)
  let imports := runtimeOperations.mapIdx Fir.Wasm.runtimeImport ++ externalImports
  let exports := rewrites.foldl (init := module.exports)
    fun exports (_, name) => Fir.Wasm.addUnique exports name
  let result := {
    specialized with
    imports
    functions
    exports
    runtimeOperations }
  if validate then
    match Fir.Wasm.validateModule result with
    | .ok () => return result
    | .error error => throw (.invalidOutput error)
  else return result

def exampleDescriptors : Array (Array AbiKind) :=
  #[#[.tobject, .uint8, .tobject]]

def exampleOperations : Array RuntimeOp := #[
  .dec 1 true none,
  .dec 1 false (some 2),
  .delete]

def exampleCheckedCaller : Function := {
  name := `resident_dec_checked
  params := #[(objectParam, .tobject)]
  results := #[]
  locals := #[]
  body := [
    .localGet objectParam,
    .call (.runtime exampleOperations[0]!),
    .ret] }

def examplePreciseObjectCheckedCaller : Function := {
  name := `resident_dec_checked_object
  params := #[(objectParam, .object)]
  results := #[]
  locals := #[]
  body := [
    .localGet objectParam,
    .call (.runtime (.dec 1 true none)),
    .ret] }

def examplePreciseTaggedCheckedCaller : Function := {
  name := `resident_dec_checked_tagged
  params := #[(objectParam, .tagged)]
  results := #[]
  locals := #[]
  body := [
    .block ⟨`nested⟩ [
      .loop ⟨`nestedLoop⟩ [
        .localGet objectParam,
        .call (.runtime (.dec 1 true (some 2)))]],
    .ret] }

def exampleSpecializationModule : Module := {
  imports := #[Fir.Wasm.runtimeImport 0 (.dec 1 true none)]
  functions := #[
    examplePreciseObjectCheckedCaller,
    { examplePreciseTaggedCheckedCaller with
      body := [
        .localGet objectParam,
        .call (.runtime (.dec 1 true none)),
        .ret] }]
  exports := #[
    examplePreciseObjectCheckedCaller.name,
    examplePreciseTaggedCheckedCaller.name]
  initializers := #[]
  runtimeOperations := #[.dec 1 true none]
  closureDescriptors := exampleDescriptors
  memory := some ResidentRuntime.residentMemory }

def residentSpecializationExample : Except String Module :=
  internalizeReleases exampleSpecializationModule
    |>.mapError fun error => s!"release specialization: {repr error}"

def exampleUncheckedCaller : Function := {
  name := `resident_dec_unchecked
  params := #[(objectParam, .tobject)]
  results := #[]
  locals := #[]
  body := [
    .localGet objectParam,
    .call (.runtime exampleOperations[1]!),
    .ret] }

def exampleDeleteCaller : Function := {
  name := `resident_delete
  params := #[(objectParam, .object)]
  results := #[]
  locals := #[]
  body := [
    .localGet objectParam,
    .call (.runtime exampleOperations[2]!),
    .ret] }

def exampleModule : Module := {
  imports := exampleOperations.mapIdx Fir.Wasm.runtimeImport
  functions := #[
    exampleCheckedCaller,
    exampleUncheckedCaller,
    exampleDeleteCaller]
  exports := #[
    exampleCheckedCaller.name,
    exampleUncheckedCaller.name,
    exampleDeleteCaller.name]
  initializers := #[]
  runtimeOperations := exampleOperations
  closureDescriptors := exampleDescriptors
  memory := some ResidentRuntime.residentMemory }

def residentExampleModule : Except String Module :=
  internalizeReleases exampleModule
    |>.mapError fun error => s!"releases: {repr error}"

/-- Production-order allocator plus release fixture for exact dead-block reuse. -/
def residentRecyclingExampleModule : Except String Module := do
  let allocated ← ResidentAllocator.install exampleModule
    |>.mapError fun error => s!"allocator: {repr error}"
  internalizeReleases allocated
    |>.mapError fun error => s!"recycling releases: {repr error}"

def manifest : Json :=
  Json.mkObj [
    ("entries", Json.arr #[
      Json.mkObj [("entry", exampleCheckedCaller.name.toString)],
      Json.mkObj [("entry", exampleUncheckedCaller.name.toString)],
      Json.mkObj [("entry", exampleDeleteCaller.name.toString)]]),
    ("constructorFieldLimit", constructorFieldLimit),
    ("closureDescriptors", Json.arr <|
      exampleDescriptors.map fun descriptor =>
        Json.arr (descriptor.map fun kind => Json.str (toString (repr kind)))),
    ("status", "generation-only; W6 recursive-release contract proof pending")]

#guard probeCompleteHeader == [
  .localGet addressLocal,
  .i32Load .uint32 (u32 headerAux3Offset),
  .localSet descriptorLocal]

#guard recyclingReleaseHeaderFunction.body == releaseHeaderBody true
#guard !recyclingReleaseHeaderFunction.body.contains
  (Instruction.call (.declaration ResidentAllocator.recycleName))
#guard (finishReleaseBody true).contains
  (Instruction.call (.declaration ResidentAllocator.recycleName))

#guard match liveReleaseBody exampleDescriptors with
  | .ok body => body.take probeCompleteHeader.length == probeCompleteHeader
  | .error _ => false

#guard match ordinaryReleaseBody exampleDescriptors with
  | .ok body => body.take 3 == [
      .localGet addressLocal,
      .i32Load .uint32 (u32 headerRefCountOffset),
      .localSet refCountLocal]
  | .error _ => false

#guard match decrementOnceBody exampleDescriptors,
    decrementOnceFunction exampleDescriptors with
  | .ok body, .ok function => function.body == body
  | _, _ => false

#guard match decrementWrapper 0 1 true with
  | .ok function => function.body == checkedDecrementCalls
      (decrementOnceCall true) ++ [.ret]
  | .error _ => false

#guard checkedDecrementLocal objectParam == checkedDecrementCalls
  (decrementOnceCall true)

#guard (specializeCheckedDecrementFunction exampleCheckedCaller).body ==
  exampleCheckedCaller.body

#guard (specializeCheckedDecrementFunction
    examplePreciseObjectCheckedCaller).body == [
  .localGet objectParam,
  .call (.runtime (.dec 1 false none)),
  .ret]

#guard (specializeCheckedDecrementFunction
    examplePreciseTaggedCheckedCaller).body == [
  .block ⟨`nested⟩ [.loop ⟨`nestedLoop⟩ []],
  .ret]

#guard match residentSpecializationExample with
  | .ok module =>
      module.imports.isEmpty &&
      module.runtimeOperations.isEmpty &&
      (module.functions.find? (fun function =>
        function.name == examplePreciseObjectCheckedCaller.name)).any
          (fun function => function.body == [
            .localGet objectParam,
            .call (.declaration (releaseName 0)),
            .ret]) &&
      (module.functions.find? (fun function =>
        function.name == examplePreciseTaggedCheckedCaller.name)).any
          (fun function => function.body == [.ret]) &&
      (module.functions.find? (fun function =>
        function.name == releaseName 0)).any
          (fun function => function.body ==
            decrementOnceCall false ++ [.ret])
  | .error _ => false

#guard match decrementWrapper 1 1 false with
  | .ok function => function.body == decrementOnceCall false ++ [.ret]
  | .error _ => false

#guard match decrementWrapper 2 0 true with
  | .ok function => function.body == [.ret]
  | .error _ => false

#guard match residentExampleModule with
  | .ok module =>
      module.imports.isEmpty &&
      module.runtimeOperations.isEmpty &&
      module.exports.contains exampleCheckedCaller.name &&
      module.exports.contains exampleUncheckedCaller.name &&
      module.exports.contains exampleDeleteCaller.name &&
      module.closureDescriptors == exampleDescriptors &&
      module.memory == some ResidentRuntime.residentMemory &&
      (Fir.Wasm.validateModule module |>.isOk) &&
      (Fir.Wasm.Emit.encode module |>.isOk)
  | .error _ => false

end Fir.Wasm.Emit.ResidentRelease
