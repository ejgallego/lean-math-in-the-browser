import Lake
open Lake DSL

package tunnell_vir

require lean_vir from git
  "https://github.com/ejgallego/lean-vir" @ "cdba5cac11eb3ee9867b8039c05f66da4e4cfaf5"

@[default_target]
lean_lib Tunnell

@[default_target]
lean_lib Bench

lean_exe tunnell_cli where
  root := `Main
