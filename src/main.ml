open Types
open Utilities
open Functions
open Records
open Structures
open Enums
open Unions
open Blocks
open Dependency
open Provider
open Mutations

let cpp_cleanup_code_for_declaration d =
  match d with
  | Dstructure s -> ""
  | Denum e -> cpp_cleanup_code_for_enum e
  | Dunion u -> cpp_cleanup_code_for_union u
  | Dfunction f -> ""
  | Dprovider p -> ""
  | Dprevious_release_version ufv -> ""
  | Drecord r -> ""
  | Ddependency d -> ""
  | Dmutation m -> ""
  | Dmanual_structure s -> ""

let cpp_cleanup_code_for_block (_, _, decl) =
  match decl with Some d -> cpp_cleanup_code_for_declaration d | None -> ""

let hpp_string_of_declaration account_id type_app_id fun_app_id namespace env d
    =
  match d with
  | Dstructure s -> hpp_string_of_structure type_app_id namespace env s
  | Denum e -> hpp_string_of_enum account_id type_app_id namespace e
  | Dunion u -> hpp_string_of_union account_id type_app_id namespace u
  | Dfunction f -> hpp_code_for_function account_id fun_app_id namespace f
  | Dprovider p -> ""
  | Dprevious_release_version ufv -> ""
  | Drecord r -> ""
  | Ddependency d -> ""
  | Dmutation m -> ""
  | Dmanual_structure s -> ""

let hpp_string_of_block account_id type_app_id fun_app_id namespace env
    file_path use_line_directives (line_number, block, decl) =
  ( if use_line_directives then
    "#line " ^ string_of_int line_number ^ " \"" ^ file_path ^ "\"\n"
  else "" )
  ^
  match decl with
  | Some d ->
      hpp_string_of_declaration account_id type_app_id fun_app_id namespace env
        d
  | None -> String.concat "\n" block

let cpp_string_of_declaration account_id type_app_id fun_app_id namespace env d
    =
  match d with
  | Dstructure s ->
      cpp_string_of_structure account_id type_app_id namespace env s
  | Denum e -> cpp_string_of_enum account_id type_app_id namespace e
  | Dunion u -> cpp_string_of_union account_id type_app_id namespace u
  | Dfunction f -> cpp_code_to_define_function account_id fun_app_id namespace f
  | Dprovider p -> ""
  | Dprevious_release_version ufv -> ""
  | Drecord r -> ""
  | Ddependency d -> ""
  | Dmutation m -> ""
  | Dmanual_structure s -> ""

let declaration_registration_code account_id type_app_id fun_app_id decl =
  match decl with
  | Dfunction f -> cpp_code_to_register_function account_id fun_app_id f
  | Dstructure s -> cpp_code_to_register_structure type_app_id s
  | Denum e -> cpp_code_to_register_enum type_app_id e
  | Dunion u -> cpp_code_to_register_union type_app_id u
  | Ddependency d -> cpp_code_to_register_dependency type_app_id d
  | Dprovider p -> cpp_code_to_register_provider type_app_id p
  | Dprevious_release_version ufv ->
      cpp_code_to_register_previous_release_version type_app_id ufv
  | Drecord r -> cpp_code_to_register_record type_app_id r
  | Dmutation m -> cpp_code_to_register_mutation type_app_id m
  | Dmanual_structure s ->
      cpp_code_to_register_manual_structure type_app_id s.manual_structure_id
        s.manual_structure_id s.manual_structure_revision ""

let cpp_registration_code account_id type_app_id fun_app_id file_id decls =
  cpp_code_lines
    [
      "void register_" ^ file_id ^ "_api(cradle::seri_catalog& catalog)";
      "{";
      String.concat ""
        (List.map
           (declaration_registration_code account_id type_app_id fun_app_id)
           decls);
      "}";
    ]

let contains_substring s1 s2 =
  let re = Str.regexp_string s2 in
  try
    ignore (Str.search_forward re s1 0);
    true
  with Not_found -> false

exception InvalidArguments

let main () =
  (* Parse the command line arguments. *)
  if not (Array.length Sys.argv = 8) then raise InvalidArguments else ();
  let input_file = Sys.argv.(1) in
  let output_file = Sys.argv.(2) in
  let account_id = Sys.argv.(3) in
  let type_app_id = Sys.argv.(4) in
  let fun_app_id = Sys.argv.(5) in
  let file_id = Sys.argv.(6) in
  let namespace = Sys.argv.(7) in

  (* Check if '#line' statements have been disabled. *)
  let use_line_directives =
    try
      ignore (Sys.getenv "CRADLE_PREPROCESSOR_DISABLE_LINE_DIRECTIVES");
      false
    with Not_found -> true
  in

  (* Parse the input file. *)
  let lines = read_file_as_lines input_file in
  let blocks = group_lines_into_blocks lines in

  (* Search for blocks that contain lines starting with "api(" and parse
     these into declarations, and then associate the declarations with the
     blocks. *)
  let decl_blocks : (int * string list * declaration option) list =
    List.map
      (fun (line_number, block) ->
        if
          List.exists (fun s -> Str.string_match (Str.regexp "^api(") s 0) block
        then (line_number, block, Some (parse_block block))
        else (line_number, block, None))
      blocks
  in

  (* Extract only the declarations. *)
  let declarations =
    List.fold_right
      (fun (line_number, block, d) decls ->
        match d with Some decl -> (line_number, decl) :: decls | None -> decls)
      decl_blocks []
  in
  let _, pure_declarations = List.split declarations in

  (* Generate C++ header. *)
  let hpp_channel = open_out output_file in
  let hpp_code =
    "// THIS FILE WAS AUTOMATICALLY GENERATED BY THE PREPROCESSOR.\n"
    ^ "// DO NOT EDIT!\n"
    ^ "\n"
    ^ "#ifndef THINKNODE_ACCOUNT" ^ "\n"
    ^ "#define THINKNODE_ACCOUNT \"" ^ account_id ^ "\"\n"
    ^ "#endif" ^ "\n"
    ^ "#ifndef THINKNODE_FUNCTION_APP" ^ "\n"
    ^ "#define THINKNODE_FUNCTION_APP \"" ^ fun_app_id ^ "\"\n"
    ^ "#endif"
    ^ "\n"
    ^ "#ifndef THINKNODE_TYPES_APP" ^ "\n"
    ^ "#define THINKNODE_TYPES_APP \"" ^ type_app_id ^ "\"\n"
    ^ "#endif" ^ "\n"
    ^ "#include <astroid/preprocessed.h>\n"
    (* Emit the clean up code. *)
    ^ String.concat "\n\n" (List.map cpp_cleanup_code_for_block decl_blocks)
    ^ String.concat "\n\n"
        (List.map
           (fun block ->
             cpp_cleanup_code_for_block block
             ^ hpp_string_of_block account_id type_app_id fun_app_id namespace
                 pure_declarations input_file use_line_directives block)
           decl_blocks)
    ^ "\n"
  in
  output_string hpp_channel hpp_code;

  (* Generate C++ code. *)
  let cpp_channel =
    open_out (Str.global_replace (Str.regexp_string ".hpp") ".cpp" output_file)
  in
  let output_file_leaf_name =
    let last_slash = String.rindex output_file '/' in
    String.sub output_file (last_slash + 1)
      (String.length output_file - (last_slash + 1))
  in
  let cpp_code =
    "// THIS FILE WAS AUTOMATICALLY GENERATED BY THE PREPROCESSOR.\n"
    ^ "// DO NOT EDIT!\n"
    ^ "\n"
    ^ "#include <algorithm>\n"
    ^ "#include <typeinfo>\n" ^ "#include \"" ^ output_file_leaf_name ^ "\"\n"
    ^ "#include <astroid/preprocessed.h>\n"
    ^ "#include <cradle/inner/resolve/seri_catalog.h>\n"
    ^ "#include <boost/algorithm/string/case_conv.hpp>\n"
    ^ "\n"
    ^ "namespace " ^ namespace ^ " {\n" ^
    "\n"
    ^ String.concat ""
        (List.map
           (fun (line, declaration) ->
             ( if use_line_directives then
               "#line " ^ string_of_int line ^ " \"" ^ input_file ^ "\"\n"
             else "" )
             ^ cpp_string_of_declaration account_id type_app_id fun_app_id
                 namespace pure_declarations declaration
             ^ "\n\n")
           declarations)
    ^ "}\n"
    ^ "\n"
    ^ "namespace " ^ namespace ^ " {\n"
    ^ cpp_registration_code account_id type_app_id fun_app_id file_id
        pure_declarations
    ^ "\n"
    ^ "}\n"
  in
  output_string cpp_channel cpp_code;

  ()

let _ = Printexc.print main ()
