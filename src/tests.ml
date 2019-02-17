
let test_pool =
  let new_id = Utils.Id.new_id_function () in
  let g = Pool.empty_global in
  let e1 = new_id () in
  let e2 = new_id () in
  let e3 = new_id () in
  let g = Pool.add_element g e1 [] in
  let g = Pool.add_element g e2 [] in
  let g = Pool.add_element g e3 [] in
  let p = Pool.empty g in
  print_endline ("is_empty empty = " ^ string_of_bool (Pool.is_empty p)) ;
  print_endline ("pick empty = " ^ match Pool.pick p with None, _ -> "None" | Some _, _ -> "Some") ;
  print_endline ("pop empty = " ^ match Pool.pop p with None, _ -> "None" | Some _, _ -> "Some") ;
  let p = Pool.add p e1 in
  let p = Pool.add p e2 in
  let p = Pool.add p e3 in
  print_endline ("is_empty [e1; e2; e3] = " ^ string_of_bool (Pool.is_empty p)) ;
  let rec foo p =
    let o, p = Pool.pop p in
    match o with
    | None -> "[]"
    | Some _ -> ";" ^ foo p in
  print_endline ("pop* [e1; e2; e3] = " ^ foo p) ;
  let rec bar i p =
    if i = 0 then "-"
    else
      let o, p = Pool.pick p in
      match o with
      | None -> "[]"
      | Some _ -> ";" ^ bar (i - 1) p in
  print_endline ("pick^10 [e1; e2; e3] = " ^ bar 10 p)

let test_relations =
  let open Relation in
  let b = [ Neutral; Hate; Trust; Chaotic; Undetermined; Avoidance ] in
  let l =
    List.map (fun r -> Basic r, false) b @
    List.concat (List.map (fun r1 -> List.map (fun r2 -> Asymmetrical (r1, r2), false) b) b) @
    List.concat (List.map (fun r1 -> List.map (fun r2 -> Explosive (Basic r1, Basic r2), false) b) b)
  in
  for i = 0 to 5 do
    let r1 = Utils.select_any l in
    let r2 = Utils.select_any l in
    let r = compose r1 r2 in
    print_string (to_string r1) ;
    print_string " composed with " ;
    print_string (to_string r2) ;
    print_string " returns " ;
    print_string (to_string r) ;
    print_string " (final complexity of " ;
    print_int (complexity r) ;
    print_string " and difficulty of " ;
    print_int (difficulty r) ;
    print_string ")." ;
    print_newline ()
  done

let test_parser =
  print_endline ("Total number of files: " ^
                 string_of_int (List.length MurderFiles.files)) ;
  let read_file f =
    print_endline ("Reading file " ^ f) ;
    let buf = Lexing.from_channel (open_in f) in
    Driver.parse_lexbuf f buf in
  let asts = List.map read_file MurderFiles.files in
  let i =
    List.fold_left Driver.prepare_declarations Driver.empty_intermediary asts in
  if not (Driver.is_intermediary_final i) then
    print_endline "Non final intermediary!" ;
  let s = Driver.parse i in
  ()

