(* This file contains code for preprocessing C++ functions. *)

open Types
open Utilities

(* C++ functions can return void, but void is not considered a regular CRADLE
   type, so functions that return void are altered so that they return nil
   instead. *)
let sanitize_return_type t = if is_void t then [ Tid "nil_type" ] else t

(* Get the actual return *value* type of a function, which is nested for
coroutines. *)
let return_value_type f =
  let sanitized = sanitize_return_type f.function_return_type in
  if f.function_is_coro then
    (List.append sanitized [Tseparator; Tid "value_type" ])
  else
    sanitized


exception InvalidNonconstReferenceParameter

(* Given an unresolved_function_declaration, this resolves all the function
   options and returns a normal function_declaration. *)
let resolve_function_options f =
  let has_monitoring_option options =
    List.exists
      (fun o -> match o with FOmonitored -> true | _ -> false)
      options
  in

  let has_trivial_option options =
    List.exists (fun o -> match o with FOtrivial -> true | _ -> false) options
  in

  let has_remote_option options =
    List.exists (fun o -> match o with FOremote -> true | _ -> false) options
  in

  let has_internal_option options =
    List.exists
      (fun o -> match o with FOinternal -> true | _ -> false)
      options
  in

  let has_disk_cached_option options =
    List.exists
      (fun o -> match o with FOdisk_cached -> true | _ -> false)
      options
  in

  let has_reported_option options =
    List.exists
      (fun o -> match o with FOreported -> true | _ -> false)
      options
  in

  let rec get_variants_option options =
    let rec check_for_duplicates others =
      match others with
      | [] -> ()
      | o :: rest -> (
          match o with
          | FOvariants _ -> raise DuplicateOption
          | _ -> check_for_duplicates rest )
    in
    match options with
    | [] -> []
    | o :: rest -> (
        match o with
        | FOvariants v ->
            check_for_duplicates rest;
            v
        | _ -> get_variants_option rest )
  in

  let rec get_revision_option options =
    let rec check_for_duplicates others =
      match others with
      | [] -> ()
      | o :: rest -> (
          match o with
          | FOrevision _ -> raise DuplicateOption
          | _ -> check_for_duplicates rest )
    in
    match options with
    | [] -> 0
    | o :: rest -> (
        match o with
        | FOrevision v ->
            check_for_duplicates rest;
            v
        | _ -> get_revision_option rest )
  in

  let rec get_name_option options default_name =
    let rec check_for_duplicates others =
      match others with
      | [] -> ()
      | o :: rest -> (
          match o with
          | FOname _ -> raise DuplicateOption
          | _ -> check_for_duplicates rest )
    in
    match options with
    | [] -> default_name
    | o :: rest -> (
        match o with
        | FOname n ->
            check_for_duplicates rest;
            n
        | _ -> get_name_option rest default_name )
  in

  let rec get_execution_class_option options default_class =
    let rec check_for_duplicates others =
      match others with
      | [] -> ()
      | o :: rest -> (
          match o with
          | FOexecution_class _ -> raise DuplicateOption
          | _ -> check_for_duplicates rest )
    in
    match options with
    | [] -> default_class
    | o :: rest -> (
        match o with
        | FOexecution_class c ->
            check_for_duplicates rest;
            c
        | _ -> get_execution_class_option rest default_class )
  in

  let rec get_upgrade_version_option options default_version =
    let rec check_for_duplicates others =
      match others with
      | [] -> ()
      | o :: rest -> (
          match o with
          | FOupgrade_version _ -> raise DuplicateOption
          | _ -> check_for_duplicates rest )
    in
    match options with
    | [] -> default_version
    | o :: rest -> (
        match o with
        | FOupgrade_version c ->
            check_for_duplicates rest;
            c
        | _ -> get_upgrade_version_option rest default_version )
  in

  let rec get_level_option options =
    let rec check_for_duplicates others =
      match others with
      | [] -> ()
      | o :: rest -> (
          match o with
          | FOlevel _ -> raise DuplicateOption
          | _ -> check_for_duplicates rest )
    in
    match options with
    | [] ->
        1 (*Set the default level to 1 if not found in the function options*)
    | o :: rest -> (
        match o with
        | FOlevel l ->
            check_for_duplicates rest;
            l
        | _ -> get_level_option rest )
  in

  let (context_type, pure_parameters) =
    match f.ufd_parameters with
    | [] ->
        (None, [])
    | p :: rest ->
       (match p.parameter_by_reference with
        | PRnonconst ->
            if p.parameter_id = "ctx" then
              (Some p.parameter_type, rest)
            else
              raise InvalidNonconstReferenceParameter
        | _ -> (None, p :: rest))
  in

  let rec validate_parameters parameters =
    match parameters with
    | [] -> ()
    | p :: rest ->
        match p.parameter_by_reference with
        | PRnonconst -> raise InvalidNonconstReferenceParameter
        | _ -> (validate_parameters rest)
  in

  let _ = (validate_parameters pure_parameters) in

  {
    function_variants = get_variants_option f.ufd_options;
    function_id = f.ufd_id;
    function_description = f.ufd_description;
    function_template_parameters = f.ufd_template_parameters;
    function_parameters = pure_parameters;
    function_return_type = f.ufd_return_type;
    function_return_description = f.ufd_return_description;
    function_body = f.ufd_body;
    function_has_monitoring = has_monitoring_option f.ufd_options;
    function_context_type = context_type;
    function_is_coro = f.ufd_is_coro;
    function_is_trivial = has_trivial_option f.ufd_options;
    function_is_remote = has_remote_option f.ufd_options;
    function_is_internal = has_internal_option f.ufd_options;
    function_is_disk_cached = has_disk_cached_option f.ufd_options;
    function_is_reported = has_reported_option f.ufd_options;
    function_revision = get_revision_option f.ufd_options;
    function_public_name = get_name_option f.ufd_options f.ufd_id;
    function_execution_class = get_execution_class_option f.ufd_options "cpu.x1";
    function_upgrade_version = get_upgrade_version_option f.ufd_options "0.0.0";
    function_level = get_level_option f.ufd_options;
  }

(* Generate the C++ code to produce the info for a function parameter.
   The generated code will push the info onto the C++ vector whose ID is
   passed in 'info_vector'. *)
let cpp_code_for_parameter_info assignments info_vector p =
  "{ " ^ "cradle::api_function_parameter_info p; " ^ "p.name = \""
  ^ p.parameter_id ^ "\"; " ^ "p.description = \""
  ^ String.escaped p.parameter_description
  ^ "\"; " ^ "using cradle::get_type_info; "
  ^ "p.schema = make_api_type_info(get_type_info("
  ^ cpp_code_for_parameterized_type assignments p.parameter_type
  ^ "())); " ^ info_vector ^ ".push_back(p); " ^ "} "

(* Generate the C++ code to produce the info for a list of function
   parameters. All info is pushed to the C++ vector whose ID is passed in
   info_vector. *)
let cpp_code_for_parameter_list_info assignments info_vector parameters =
  String.concat ""
    (List.map (cpp_code_for_parameter_info assignments info_vector) parameters)

(* Generate the C++ code to get a function parameter from a list of dynamic
   values. *)
let cpp_code_to_get_parameter_from_dynamic_list assignments p =
  cpp_code_lines
    [
      cpp_code_for_parameterized_type assignments p.parameter_type
      ^ " " ^ p.parameter_id ^ ";";
      "try";
      "{";
      "    from_dynamic(&" ^ p.parameter_id ^ ", *arg_i);";
      "}";
      "catch (boost::exception& e)";
      "{";
      "    cradle::add_dynamic_path_element(e, \"" ^ p.parameter_id ^ "\");";
      "    throw;";
      "}";
      "++arg_i;";
    ]

(* Generate the C++ code to get a function parameter from a mapping of strings
   to dynamic values. *)
let cpp_code_to_get_parameter_from_dynamic_map assignments p =
  cpp_code_lines
    [
      cpp_code_for_parameterized_type assignments p.parameter_type
      ^ " " ^ p.parameter_id ^ ";";
      "try";
      "{";
      "    from_dynamic(";
      "        &" ^ p.parameter_id ^ ",";
      "        get_field(args, \"" ^ p.parameter_id ^ "\"));";
      "}";
      "catch (boost::exception& e)";
      "{";
      "    cradle::add_dynamic_path_element(e, \"" ^ p.parameter_id ^ "\");";
      "    throw;";
      "}";
    ]

(* Generate the C++ code to get a function parameter from a list of
   untyped_immutables. *)
let cpp_code_to_get_parameter_from_immutable_list assignments p =
  let parameter_type =
    cpp_code_for_parameterized_type assignments p.parameter_type
  in

  cpp_code_lines
    [
      parameter_type ^ " const* " ^ p.parameter_id ^ ";";
      "try";
      "{";
      "    cradle::cast_immutable_value(";
      "        &" ^ p.parameter_id ^ ",";
      "        get_value_pointer(*arg_i));";
      "}";
      "catch (boost::exception& e)";
      "{";
      "    cradle::add_dynamic_path_element(e, \"" ^ p.parameter_id ^ "\");";
      "    throw;";
      "}";
      "++arg_i;";
    ]

(* Construct the code to call a function f once the arguments have been
   retrieved.
   This assumes that the actual argument values are already stored in
   variables with the same names as the function parameters.
   If args_as_pointers is true, those variables are assumed to be pointers
   to values, so code will be emitted to dereference them. *)
let cpp_code_to_call_function f id args_as_pointers =
  id ^ "("
  ^ ( if f.function_has_monitoring then
      "check_in,reporter"
      ^ match f.function_parameters with [] -> "" | _ -> ","
    else "" )
  ^ String.concat ","
      (List.map
         (fun p -> (if args_as_pointers then "*" else "") ^ p.parameter_id)
         f.function_parameters)
  ^ ")"

(* Generate the C++ code to define a single instantiation of a function. *)
let cpp_code_to_define_function_instance account_id app_id f label assignments =
  let full_public_name = f.function_public_name ^ label in

  "struct " ^ full_public_name ^ "_fn_def : cradle::api_function_interface "
  ^ "{ " ^ full_public_name ^ "_fn_def() " ^ "{ " ^ "api_info.name = \""
  ^ full_public_name ^ "\"; " ^ "api_info.description = \""
  ^ String.escaped f.function_description
  ^ "\"; " ^ "implementation_info.account_id = \"" ^ account_id ^ "\"; "
  ^ "implementation_info.app_id = \"" ^ app_id ^ "\"; "
  ^ "implementation_info.upgrade_version = \""
  ^ String.lowercase (String.escaped f.function_upgrade_version)
  ^ "\"; "
  ^ "implementation_info.flags = cradle::api_function_flag_set(NO_FLAGS) "
  ^ (if f.function_has_monitoring then "| FUNCTION_HAS_MONITORING " else "")
  ^ (if f.function_is_trivial then "| FUNCTION_IS_TRIVIAL " else "")
  ^ ( if f.function_upgrade_version <> "0.0.0" then "| FUNCTION_IS_UPGRADE "
    else "" )
  ^ (if f.function_is_remote then "| FUNCTION_IS_REMOTE " else "")
  ^ (if f.function_is_disk_cached then "| FUNCTION_IS_DISK_CACHED " else "")
  ^ (if f.function_is_reported then "| FUNCTION_IS_REPORTED " else "")
  ^ "; " ^ "implementation_info.level = "
  ^ string_of_int f.function_level
  ^ "; " ^ "api_info.execution_class = \""
  ^ String.lowercase (String.escaped f.function_execution_class)
  ^ "\"; " ^ "api_function_type_info type_info; "
  ^ cpp_code_for_parameter_list_info assignments "type_info.parameters"
      f.function_parameters
  ^ "using cradle::get_type_info; "
  ^ "type_info.returns.schema = make_api_type_info(get_type_info("
  ^ cpp_code_for_parameterized_type assignments (return_value_type f)
  ^ "())); " ^ "type_info.returns.description = \""
  ^ String.escaped f.function_return_description
  ^ "\"; "
  ^ "api_info.schema = make_api_type_info_with_function_type(type_info); "
  ^ "implementation_info.uid = generate_function_uid(api_info.name, "
  ^ "type_info.parameters, "
  ^ string_of_int f.function_revision
  ^ "); " ^ "} "
  ^
  (* Construct code to call the function and extract its return value. *)
  let code_to_call_function args_as_pointers =
    cpp_code_to_call_function f f.function_id args_as_pointers
  in
  let code_to_evaluate_function_dynamically =
    "cradle::dynamic fn_result; "
    ^
    if is_void f.function_return_type then
      code_to_call_function false ^ "; set(fn_result, nil); "
    else "to_dynamic(&fn_result, " ^ code_to_call_function false ^ "); "
  in

  (* Emit code to call the function with a list of dynamic values as
     arguments. *)
  "cradle::dynamic execute( " ^ "cradle::check_in_interface& check_in, "
  ^ "cradle::progress_reporter_interface& reporter, "
  ^ "cradle::dynamic_array const& args) const " ^ "{ " ^ "if (args.size() != "
  ^ string_of_int (List.length f.function_parameters)
  ^ ") " ^ "throw cradle::exception(\"wrong number of arguments (expected "
  ^ string_of_int (List.length f.function_parameters)
  ^ ")\"); " ^ "cradle::dynamic_array::const_iterator arg_i = args.begin(); "
  ^ String.concat ""
      (List.map
         (cpp_code_to_get_parameter_from_dynamic_list assignments)
         f.function_parameters)
  ^ code_to_evaluate_function_dynamically ^ "return fn_result; " ^ "} "
  (* Emit code to call the function with the arguments passed as a map of
     strings to dynamic values. *)
  ^ "cradle::dynamic execute("
  ^ "cradle::check_in_interface& check_in, "
  ^ "cradle::progress_reporter_interface& reporter, "
  ^ "cradle::dynamic_map const& args) const " ^ "{ "
  ^ String.concat ""
      (List.map
         (cpp_code_to_get_parameter_from_dynamic_map assignments)
         f.function_parameters)
  ^ code_to_evaluate_function_dynamically ^ "return fn_result; " ^ "} "
  (* Emit code to call the function with a list of untyped_immutables as
     arguments. *)
  ^ "untyped_immutable "
  ^ "execute( " ^ "cradle::check_in_interface& check_in, "
  ^ "cradle::progress_reporter_interface& reporter, "
  ^ "std::vector<cradle::untyped_immutable> const& args) " ^ "const " ^ "{ "
  ^ "if (args.size() != "
  ^ string_of_int (List.length f.function_parameters)
  ^ ") " ^ "throw cradle::exception(\"wrong number of arguments (expected "
  ^ string_of_int (List.length f.function_parameters)
  ^ ")\"); " ^ "std::vector<cradle::untyped_immutable>::const_iterator "
  ^ "arg_i = args.begin(); "
  ^ String.concat ""
      (List.map
         (cpp_code_to_get_parameter_from_immutable_list assignments)
         f.function_parameters)
  ^ ( if is_void f.function_return_type then
      "assert(false); " ^ "return erase_type(make_immutable(nil)); "
    else
      "auto result = " ^ code_to_call_function true ^ "; "
      ^ "return swap_in_and_erase_type(result); " )
  ^ "} " ^ "}; "

(* Generate the C++ code to for a function definition. *)
let cpp_function_definition f is_static id body =
  ( if List.length f.function_template_parameters == 0 then
    if is_static then "static inline " else ""
  else template_parameters_declaration f.function_template_parameters )
  ^ cpp_code_for_type f.function_return_type
  ^ " " ^ id ^ "("
  ^ ( if f.function_has_monitoring then
      "check_in_interface& check_in," ^ "progress_reporter_interface& reporter"
      ^ match f.function_parameters with [] -> "" | _ -> ","
    else "" )
  ^ ( match f.function_context_type with
      | Some context_type ->
        (cpp_code_for_type context_type) ^ "& ctx"
        ^ (match f.function_parameters with [] -> "" | _ -> ",")
      | None -> "")
  ^ String.concat ","
      (List.map
         (fun p ->
           cpp_code_for_type p.parameter_type
           ^ " "
           ^ (match p.parameter_by_reference with
              | PRconst -> "const&"
              | PRnonconst -> "&"
              | PRnone -> "")
           ^ " " ^ p.parameter_id)
         f.function_parameters)
  ^ ") " ^ body

(* This declares/defines a function in a header file.
   If the function has template arguments and a body is given, the body must
   be supplied so that it's visible to callers.
   Otherwise, this simply declares the function and omits the body. *)
let hpp_function_declaration f id =
  cpp_function_definition f false id
    ( if List.length f.function_template_parameters != 0 then
      match f.function_body with Some code -> code | _ -> "; "
    else "; " )

(* Given a generator function, this calls it for each instance of a function
   to generate code for that instance, and then concatenates the results. *)
let concat_code_for_function_instances generator f =
  let instantiations = enumerate_combinations f.function_variants in
  String.concat ""
    (List.map
       (fun (assignments, label) ->
         generator f assignments f.function_id f.function_public_name
           (f.function_public_name ^ label))
       instantiations)

(* Generate the CPP file code to redirect an API instance of a function to
   the original C++ function. *)
(* TODO: Update this. *)
let cpp_function_redirection_code f assignments cpp_id public_id full_public_id
    =
  cpp_code_for_parameterized_type assignments
    (sanitize_return_type f.function_return_type)
  ^ " " ^ full_public_id ^ "_api("
  ^ String.concat ", "
      (List.map
         (fun p ->
           ""
           ^ cpp_code_for_parameterized_type assignments p.parameter_type
           ^ " const& " ^ p.parameter_id)
         f.function_parameters)
  ^ ") " ^ "{ "
  ^ ( if f.function_has_monitoring then
      "null_check_in check_in; " ^ "null_progress_reporter reporter; "
    else "" )
  ^ "return " ^ cpp_id ^ "("
  ^ ( if f.function_has_monitoring then
      "check_in,reporter"
      ^ match f.function_parameters with [] -> "" | _ -> ","
    else "" )
  ^ String.concat "," (List.map (fun p -> p.parameter_id) f.function_parameters)
  ^ "); " ^ "} "

(* Generate all the code that needs to appear in the CPP file for a single
   function definition. *)
let cpp_code_to_define_function account_id app_id namespace f =
  let instantiations = enumerate_combinations f.function_variants in
  ""
  (* String.concat ""
    (List.map
       (fun (assignments, label) ->
         cpp_code_to_define_function_instance account_id app_id f label
           assignments)
       instantiations) *)
  (* Define all the API instance redirections. *)
  (* ^ concat_code_for_function_instances cpp_function_redirection_code f *)
  (* Define the request interface. *)
  (* ^ define_request_interface_for_function account_id app_id f *)
  ^
  if List.length f.function_template_parameters == 0 then
    match f.function_body with
    (* If the function has no template parameters and a body is given
       for it, that body must be defined in the generated cpp file. *)
    | Some body -> cpp_function_definition f false f.function_id body
    | _ -> ""
  else ""

(* Generate the C++ code to register a function instance as part of an API. *)
let cpp_code_to_register_function_instance f label assignments =
  let full_public_name = f.function_public_name ^ label in
  if not f.function_is_internal then
    "catalog.register_resolver(rq_" ^ full_public_name ^ "("
    ^ String.concat ", "
      (List.map
          (fun p ->
            cpp_code_for_parameterized_type assignments p.parameter_type
            ^ "()")
          f.function_parameters)
    ^ "));\n"
  else
    ""

(* Generate the C++ code to register a function as part of an API. *)
let cpp_code_to_register_function account_id app_id f =
  let instantiations = enumerate_combinations f.function_variants in
  String.concat ""
    (List.map
       (fun (assignments, label) ->
         cpp_code_to_register_function_instance f label assignments)
       instantiations)

(* Generate the interface necessary to construct CRADLE calculation requests
   for this function instance. *)
let define_cradle_interface_for_function_instance account_id app_id f
    assignments cpp_id public_id full_public_id =
  let caching_level =
    if f.function_is_trivial then "none"
    else if f.function_is_disk_cached then "full"
    else "memory"
  in
  cpp_code_lines
    [
      "inline cppcoro::task<" ^
          (cpp_code_for_parameterized_type assignments
            (return_value_type f)) ^ ">";
      "coro_" ^ full_public_id ^ "(";
        "cradle::context_intf&"
        ^ (match f.function_context_type with
          | Some _ -> "generic_ctx"
          | None -> "") ^ ",";
      String.concat ","
        (List.map
          (fun p ->
            (cpp_code_for_parameterized_type assignments p.parameter_type)
            ^ " " ^ p.parameter_id)
          f.function_parameters);
      ")";
      "{";
        (match f.function_context_type with
          | Some context_type ->
              ("auto& ctx = cradle::cast_ctx_to_ref<" ^
              (cpp_code_for_type context_type) ^ ">(generic_ctx);")
          | None -> "");
        "auto result = "
        ^ (if f.function_is_coro then "co_await " else "")
        ^ f.function_id ^ "("
        ^ (match f.function_context_type with
          | Some _ -> "ctx,"
          | None -> "")
        ^ String.concat ","
            (List.map (fun p -> p.parameter_id) f.function_parameters)
        ^ ");";
        (match f.function_context_type with
          | Some _ -> "ctx.on_value_complete();"
          | None -> "");
        "co_return result;";
      "}";

      "template<"
      ^ String.concat ","
          (List.mapi (fun i _ -> "class Arg" ^ (string_of_int i))
            f.function_parameters)
      ^ ">";
      "requires "
      ^ String.concat " && "
          (List.mapi
            (fun i p ->
              "cradle::TypedArg<Arg" ^ (string_of_int i) ^ "," ^
              (cpp_code_for_parameterized_type assignments p.parameter_type) ^
              ">")
            f.function_parameters);
      "auto";
      "rq_" ^ full_public_id ^ "("
      ^ String.concat ", "
          (List.mapi
            (fun i p -> "Arg" ^ (string_of_int i) ^ " " ^ p.parameter_id)
            f.function_parameters)
      ^ ")";
      "{";
        "using props_type = cradle::request_props<cradle::caching_level_type::" ^
          caching_level ^ ", cradle::request_function_t::coro, true>;";
        (* TODO: Include app/version info in UUID. *)
        "cradle::request_uuid uuid{\"" ^ full_public_id ^ "\"};";
        "uuid.set_level(cradle::caching_level_type::" ^ caching_level ^ ");";
        "std::string title{\"" ^ full_public_id ^ "\"};";
        "return rq_function("
          ^ "props_type{std::move(uuid), std::move(title)},"
          ^ "coro_" ^ full_public_id ^ ","
          ^ String.concat ","
              (List.map
                (fun p ->
                  "cradle::normalize_arg<" ^
                    (cpp_code_for_parameterized_type assignments
                      p.parameter_type) ^ ", props_type>(std::move(" ^
                    p.parameter_id ^ "))")
                f.function_parameters)
          ^ ");";
      "}";

      "template<"
      ^ String.concat ","
          (List.mapi (fun i _ -> "class Arg" ^ (string_of_int i))
            f.function_parameters)
      ^ ">";
      "requires "
      ^ String.concat " && "
          (List.mapi
            (fun i p ->
              "cradle::TypedArg<Arg" ^ (string_of_int i) ^ "," ^
              (cpp_code_for_parameterized_type assignments p.parameter_type) ^
              ">")
            f.function_parameters);
      "auto";
      "rq_proxy_" ^ full_public_id ^ "("
      ^ String.concat ", "
          (List.mapi
            (fun i p -> "Arg" ^ (string_of_int i) ^ " " ^ p.parameter_id)
            f.function_parameters)
      ^ ")";
      "{";
        "using props_type = cradle::request_props<" ^
          "cradle::caching_level_type::none, " ^
          "cradle::request_function_t::proxy_coro, true>;";
        (* TODO: Include app/version info in UUID. *)
        "cradle::request_uuid uuid{\"" ^ full_public_id ^ "\"};";
        "uuid.set_level(cradle::caching_level_type::" ^ caching_level ^ ");";
        "std::string title{\"" ^ full_public_id ^ "\"};";
        "return cradle::rq_proxy<"
          ^ (cpp_code_for_parameterized_type assignments
              (return_value_type f)) ^ ">("
          ^ "props_type{std::move(uuid), std::move(title)},"
          ^ String.concat ","
              (List.map
                (fun p ->
                  "cradle::normalize_arg<" ^
                    (cpp_code_for_parameterized_type assignments
                      p.parameter_type) ^ ", props_type>(std::move(" ^
                    p.parameter_id ^ "))")
                f.function_parameters)
          ^ ");";
      "}";
    ]

(* Generate the interface necessary to construct typed calculation requests for
   this function. *)
let define_cradle_interface_for_function account_id app_id f =
  concat_code_for_function_instances
    (define_cradle_interface_for_function_instance account_id app_id)
    f

(* Generate the header file code to redirect an API instance of a function to
   the original C++ function. *)
let hpp_function_redirection_code f assignments cpp_id public_id full_public_id
    =
  cpp_code_for_parameterized_type assignments
    (sanitize_return_type f.function_return_type)
  ^ " " ^ full_public_id ^ "_api("
  ^ String.concat ", "
      (List.map
         (fun p ->
           ""
           ^ cpp_code_for_parameterized_type assignments p.parameter_type
           ^ " const& " ^ p.parameter_id)
         f.function_parameters)
  ^ "); "

(* If the function has monitoring, it requires the progress reporter and
   check-in objects to be passed in as the first two arguments. This supplies
   an overload without those. *)
let delcare_non_monitored_redirection f =
  ( if List.length f.function_template_parameters == 0 then "static inline "
  else template_parameters_declaration f.function_template_parameters )
  ^ cpp_code_for_type f.function_return_type
  ^ " " ^ f.function_id ^ "("
  ^ String.concat ","
      (List.map
         (fun p ->
           cpp_code_for_type p.parameter_type
           ^ " "
           ^ (match p.parameter_by_reference with
              | PRconst -> "const&"
              | PRnonconst -> "&"
              | PRnone -> "")
           ^ " " ^ p.parameter_id)
         f.function_parameters)
  ^ ") " ^ "{ " ^ "null_check_in check_in; "
  ^ "null_progress_reporter reporter; " ^ "return " ^ f.function_id
  ^ "(check_in,reporter"
  ^ (match f.function_parameters with [] -> "" | _ -> ",")
  ^ String.concat "," (List.map (fun p -> p.parameter_id) f.function_parameters)
  ^ "); " ^ "} "

(* Generate all the code that needs to appear in the C++ header file for a
   function. *)
let hpp_code_for_function account_id app_id namespace f =
  hpp_function_declaration f f.function_id
  (* Declare the non-monitored redirection. *)
  ^ ( if f.function_has_monitoring then delcare_non_monitored_redirection f
    else "" )
  (* Declare all the API instance redirections. *)
  (* ^ concat_code_for_function_instances hpp_function_redirection_code f *)
  ^ define_cradle_interface_for_function account_id app_id f
