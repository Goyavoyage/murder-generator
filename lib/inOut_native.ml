(** Module InOut_native
 * An implementation of [InOut.T] for native programs. **)


let pause = Lwt.return

let stopLoading = pause
let startLoading = pause

let get_file fileName =
  let file = open_in fileName in
  let rec aux _ =
    try let str = input_line file in
        str :: aux ()
    with End_of_file -> [] in
  Lwt.return (String.concat "\n" (aux ()))

let log msg =
  print_endline ("Log: " ^ msg)

let languages = [] (* TODO *)


(** A node is just a function to print this node.
 * This function takes as argument the current column, its right margin,
 * and a function to be called to yield a new line (taking into account
 * an eventual left margin), and what is currently in the current line.
 * This last function takes as argument the produced string, adds a new line
 * and the necessary spacing, then prints this string and returns the new
 * current column and the string composed of the elements added in this line.
 * Furthermore, a node takes as a argument a link printer:
 * whenever the node item wants to print a modifyable link, it calls
 * this function, which will insert a specific string for the user
 * to know how to call this particular link.
 * This function is itself given a function to update the value of
 * the node item. **)
type node =
  ((unit -> unit) -> string) ->
  int * int * (string -> string * int) * string -> string * int

(** The length of the screen as printed. **)
let screen_length = ref 100

type layout =
  | Normal
  | Centered
  | Inlined

type block =
  | Div of layout * block list
  | P of block list
  | List of bool * block list
  | Space
  | Text of string
  | Link of string * string
  | LinkContinuation of bool * string * (unit -> unit)
  | LinkFile of string * string * string * bool * (unit -> string)
  | Table of block list * block list list
  | Node of node

let rec add_spaces =
  let need_space = function
    | Div _ -> false
    | P _ -> false
    | List _ -> false
    | Space -> false
    | Text _ -> true
    | Link _ -> true
    | LinkContinuation _ -> true
    | LinkFile _ -> true
    | Table _ -> false
    | Node _ -> false in
  let rec aux = function
    | [] -> []
    | a :: [] -> a :: []
    | a :: b :: l ->
      if need_space a && need_space b then
        a :: Text " " :: aux (b :: l)
      else a :: aux (b :: l) in
  let aux l = aux (List.map add_spaces l) in function
    | Div (layout, l) -> Div (layout, aux l)
    | P l -> P (aux l)
    | List (visible, l) -> List (visible, List.map add_spaces l)
    | Table (h, l) ->
      Table (List.map add_spaces h, List.map (List.map add_spaces) l)
    | e -> e

(** Increases the current line and position by a given string. **)
let just_print str (line, current) =
  (line ^ str, current + String.length str)

let block_node b link =
  let rec aux current right_margin new_line line = function
    | Div (layout, l) ->
      let start = current in
      List.fold_left (fun (str, current) ->
        aux current right_margin (fun str ->
          match layout with
          | Normal ->
            let (str, current) = new_line str in
            let space =
              if current < start then
                String.make (start - current) ' '
              else "" in
            (str ^ space, start)
          | Centered ->
            let space = (right_margin - String.length str) / 2 in
            new_line (String.make (max 0 space) ' ' ^ str)
          | Inlined -> new_line str) str) (line, current) l
    | P l ->
      List.fold_left (fun (str, current) ->
        aux current right_margin new_line str) (just_print "  " (line, current)) l
    | List (drawn, l) ->
      List.fold_left (fun (line, current) ->
        if drawn then aux (2 + current) right_margin new_line (line ^ " *")
        else aux current right_margin new_line line) (line, current) l
    | Space ->
      if current >= right_margin then new_line line
      else just_print "  " (line, current)
    | Text str ->
      List.fold_left (fun (line, current) str ->
          let (line, current) =
            if current >= right_margin then new_line line
            else just_print " " (line, current) in
          (line ^ str, current + String.length str)) (line, current)
        (String.split_on_char ' ' str)
    | Link (text, address) ->
      let link = link (fun _ -> print_endline address) in
      aux current right_margin new_line line (Text (text ^ " " ^ link))
    | LinkContinuation (forward, text, cont) ->
      let link = link cont in
      let str =
        if forward then text ^ " " ^ link
        else link ^ " " ^ text in
      aux current right_margin new_line line (Text str)
    | LinkFile (text, fileName, mime, newlines, content) ->
      aux current right_margin new_line line (Text (text ^ " <link file>")) (* TODO *)
    | Table (headers, content) ->
      aux current right_margin new_line line (Text "<table>") (* TODO *)
    | Node node -> node link (current, right_margin, new_line, line) in
  let aux (current, right_margin, new_line, line) =
    aux current right_margin new_line line b in
  aux

(** Actions linked to each link. **)
let links = ref []

(** Starting the server. **)
let _ =
  let rec aux _ =
    (* TODO: Print all registered nodes. *)
    match%lwt Lwt_io.read_line_opt Lwt_io.stdin with
    | None -> Lwt.return ()
    | Some str ->
      let i =
        try int_of_string str
        with _ -> -1 in
      match try List.nth_opt !links i
            with _ -> None with
      | None ->
        print_endline "Invalid number." ;
        aux ()
      | Some f ->
        print_string ("[" ^ string_of_int i ^ "]: ") ;
        f () ;
        aux () in
  aux ()

let print_node ?(error = false) n =
  (* TODO: Currently, this function prints the node.
   * It should actually be the server that deals with the actual printing:
   * this function should just add the nodes in the global state. *)
  let header =
    String.make !screen_length (if error then '!' else '-') in
  let new_line str =
    print_endline str ;
    (" ", 1) in
  let link f =
    let n = List.length !links in
    links := !links @ [f] ;
    "[" ^ string_of_int n ^ "]" in
  let (str, _) =
    n link (1, !screen_length - 1, new_line, " ") in
  print_endline header ;
  print_endline str ;
  print_endline header

let print_block ?(error = false) =
  Utils.compose (print_node ~error) (Utils.compose block_node add_spaces)

let numberInput r =
  print_string (string_of_int !r ^ " -> ") ;
  flush stdout ;
  let str = input_line stdin in
  let v =
    try int_of_string str
    with _ -> print_endline "Invalid value."; !r in
  r := v

let createNumberInput ?min:(mi = 0) ?max:(ma = max_int) n =
  let v = ref n in
  let node link (current, right_margin, new_line, line) =
    just_print
      (" " ^ string_of_int !v ^ " " ^ link (fun _ ->
        numberInput v ;
        v := max mi (min !v ma))) (line, current) in
  (node, fun _ -> !v)

let createTextInput str =
  let txt = ref str in
  let node link (current, right_margin, new_line, line) =
    just_print (" <" ^ !txt ^ "> " ^ link (fun _ ->
                 print_string ("<" ^ !txt ^ "> -> ") ;
                 flush stdout ;
                 let str = input_line stdin in
                 txt := str)) (line, current) in
  (node, fun _ -> !txt)

let createPercentageInput d =
  let d = max 0. (min 1. d) in
  let v = ref (100. *. d) in
  let node link (current, right_margin, new_line, line) =
    just_print (" " ^ string_of_float !v ^ "% " ^ link (fun _ ->
      print_string (string_of_float !v ^ "% -> ") ;
      flush stdout ;
      let str = input_line stdin in
      let str =
        let len = String.length str in
        if len > 0 && str.[len - 1] = '%' then
          String.sub str 0 (len - 1)
        else str in
      let v' =
        try float_of_string str
        with _ -> print_endline "Invalid value."; !v in
      v := max 0. (min v' 100.))) (line, current) in
  (node, fun _ -> !v /. 100.)

let createDateInput d =
  let v = ref d in
  let node link (current, right_margin, new_line, line) =
    just_print (" " ^ Date.iso8601 !v ^ "% " ^ link (fun _ ->
      print_string (Date.iso8601 !v ^ "% -> ") ;
      flush stdout ;
      let str = input_line stdin in
      let v' =
        try Date.from_iso8601 str
        with _ -> print_endline "Invalid date."; !v in
      v := v')) (line, current) in
  (node, fun _ -> !v)

let createSwitch text texton textoff b f =
  let b = ref b in
  let node link (current, right_margin, new_line, line) =
    just_print (" " ^ (if !b then "[X]" else "[ ]")
                ^ link (fun _ -> b := not !b; f ())
                ^ Option.default "" (if !b then texton else textoff))
      (line, current) in
  (node, (fun v -> b := v), fun _ -> !b)

let createFileImport extensions prepare = (* TODO *)
  let node link (current, right_margin, new_line, line) =
    just_print "<file import>" (line, current) in
  (node, fun _ -> Lwt.return ("", ""))

let clear_response _ =
  links := [fun _ -> numberInput screen_length] ;
  print_newline () ;
  print_endline (String.make !screen_length '=')

