import Fir.Wasm.Emit.ResidentLinker
import Bench
import Lean.Elab.Command

open Lean Elab Command

-- One workload per module isolates unsupported operations. No JS runtime fallback.
set_option maxHeartbeats 0 in
run_cmd do
  let entry := (← IO.getEnv "FIR_MATH_ENTRY").getD "Bench.primeCount" |>.toName
  let output := (← IO.getEnv "FIR_MATH_OUT").getD "_build/primeCount.wasm"
  let capture := (← IO.getEnv "FIR_MATH_CAPTURE").getD "unit"
  let retained := Fir.Wasm.Emit.ResidentLinker.closedApplicationRetainedExternalNames
  let source ← liftCoreM <| match capture with
    | "module" => Fir.Wasm.Emit.Source.compileEntryModuleWiseInternalized entry retained
    | "unit" => Fir.Wasm.Emit.Source.compileEntriesFinalCapturedInternalized #[entry] retained
    | _ => throwError "unknown capture mode: {capture}"
  let baseResult ← liftCoreM <| Fir.Wasm.Emit.Source.compileClosedClosureModuleArtifact source
  let base ← match baseResult with
    | .ok value => pure value
    | .error error => throwError "FIR lowering failed for {entry}: {repr error}"
  match ← base.write (output ++ ".base.wasm") with
  | .ok () => pure ()
  | .error error => throwError "base artifact write failed: {repr error}"
  let linked ← match Fir.Wasm.Emit.ResidentLinker.linkArtifact
      (Fir.Wasm.Emit.ResidentLinker.closedApplicationAvailablePolicy base.module #[entry]) base with
    | .ok value => pure value
    | .error error => throwError "FIR resident link failed for {entry}: {repr error}"
  unless linked.module.imports.isEmpty && linked.module.runtimeOperations.isEmpty do
    throwError "resident package retained imports or runtime operations"
  match ← linked.write output with
  | .ok () => pure ()
  | .error error => throwError "resident artifact write failed: {repr error}"
  IO.FS.writeFile (output ++ ".functions.json") linked.functionInventoryJson.compress
  logInfo m!"generated {entry}: {source.program.decls.size} declarations, {linked.bytes.size} bytes, zero imports"
