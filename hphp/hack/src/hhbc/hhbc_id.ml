(**
 * Copyright (c) 2017, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the "hack" directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *
*)

open Hh_core

module SU = Hhbc_string_utils

(* TODO: Remove this once we start reading this off of HHVM's config.hdf *)
let default_auto_aliased_namespaces = [
  "Arrays", "HH\\Lib\\Arrays"
  ; "C", "HH\\Lib\\C"
  ; "Dict", "HH\\Lib\\Dict"
  ; "Keyset", "HH\\Lib\\Keyset"
  ; "Math", "HH\\Lib\\Math"
  ; "PHP", "HH\\Lib\\PHP"
  ; "Str", "HH\\Lib\\Str"
  ; "Vec", "HH\\Lib\\Vec"
  ]
let auto_namespace_map () =
  Option.value Hhbc_options.(aliased_namespaces !compiler_options)
    ~default:default_auto_aliased_namespaces

let elaborate_id ns kind id =
  let fully_qualified_id = snd (Namespaces.elaborate_id ns kind id) in
  let fully_qualified_id =
    Namespaces.renamespace_if_aliased
      ~reverse:true (auto_namespace_map ()) fully_qualified_id
  in
  let stripped_fully_qualified_id = SU.strip_global_ns fully_qualified_id in
  let clean_id = SU.strip_ns fully_qualified_id in
  let need_fallback =
    stripped_fully_qualified_id <> clean_id &&
    (String.contains stripped_fully_qualified_id '\\') &&
    not (String.contains (snd id) '\\')
  in
  stripped_fully_qualified_id, if need_fallback then Some clean_id else None

(* Class identifier, with namespace qualification if not global, but without
 * initial backslash.
 *)
module Class = struct
  type t = string

  let from_ast_name s =
    Hhbc_alias.normalize (SU.strip_global_ns s)
  let from_raw_string s = s
  let to_raw_string s = s
  let elaborate_id ns id =
    let mangled_name = SU.Xhp.mangle (snd id) in
    match Hhbc_alias.opt_normalize (SU.strip_global_ns mangled_name) with
    | None -> elaborate_id ns Namespaces.ElaborateClass (fst id, mangled_name)
    | Some s -> s, None

  let to_unmangled_string s =
    SU.Xhp.unmangle s
end

module Prop = struct
  type t = string

  let from_raw_string s = s
  let from_ast_name s = SU.strip_global_ns s
  let add_suffix s suffix = s ^ suffix
  let to_raw_string s = s
end

module Method = struct
  type t = string

  let from_raw_string s = s
  let from_ast_name s = SU.strip_global_ns s
  let add_suffix s suffix = s ^ suffix
  let to_raw_string s = s
end

module Function = struct
  type t = string

  (* See hphp/compiler/parser.cpp. *)
  let builtins_in_hh =
  [
    "fun";
    "meth_caller";
    "class_meth";
    "inst_meth";
    "invariant_callback_register";
    "invariant";
    "invariant_violation";
    "idx";
    "type_structure";
    "asio_get_current_context_idx";
    "asio_get_running_in_context";
    "asio_get_running";
    "xenon_get_data";
    "thread_memory_stats";
    "thread_mark_stack";
    "objprof_get_strings";
    "objprof_get_data";
    "objprof_get_paths";
    "heapgraph_create";
    "heapgraph_stats";
    "heapgraph_foreach_node";
    "heapgraph_foreach_edge";
    "heapgraph_foreach_root";
    "heapgraph_dfs_nodes";
    "heapgraph_dfs_edges";
    "heapgraph_node";
    "heapgraph_edge";
    "heapgraph_node_in_edges";
    "heapgraph_node_out_edges";
    "server_warmup_status";
    "dict";
    "vec";
    "keyset";
    "varray";
    "darray";
    "is_vec";
    "is_dict";
    "is_keyset";
    "is_varray";
    "is_darray";
  ]

  let builtins_at_top = [
    "echo";
    "exit";
    "die";
    "func_get_args";
    "func_get_arg";
    "func_num_args"
  ]

  let has_hh_prefix s =
    let s = String.lowercase_ascii s in
    String_utils.string_starts_with s "hh\\"

  let is_hh_builtin s =
    let s = if has_hh_prefix s then String_utils.lstrip s "hh\\" else s in
    List.mem builtins_in_hh s

  let from_raw_string s = s
  let to_raw_string s = s
  let add_suffix s suffix = s ^ suffix
  let elaborate_id ns id = elaborate_id ns Namespaces.ElaborateFun id
  let elaborate_id_with_builtins ns id =
    let fq_id, backoff_id = elaborate_id ns id in
    match backoff_id with
      (* OK we are in a namespace so let's look at the backoff ID and see if
       * it's an HH\ or top-level function with implicit namespace.
       *)
    | Some id ->
      if List.mem builtins_in_hh id && (Emit_env.is_hh_syntax_enabled ())
      then SU.prefix_namespace "HH" id, Some id
      else if List.mem builtins_at_top id
      then id, None
      else fq_id, backoff_id
      (* Likewise for top-level, with no namespace *)
    | None ->
      if is_hh_builtin fq_id && (Emit_env.is_hh_syntax_enabled ())
      then
        if has_hh_prefix fq_id
        then fq_id, None
        else SU.prefix_namespace "HH" fq_id, Some fq_id
      else fq_id, None
end

module Const = struct
  type t = string

  let from_ast_name s = SU.strip_global_ns s
  let from_raw_string s = s
  let to_raw_string s = s
  let elaborate_id ns id =
    let fq_id, backoff_id = elaborate_id ns Namespaces.ElaborateConst id in
    fq_id, backoff_id, String.contains (snd id) '\\'
end
