
type language = string

type tag = string

type command = bool option * tag

let generic = ""

let iso639 = Utils.id
let from_iso639 = Utils.id

let get_tag = Utils.id
let print_tag = Utils.id

type 'a t = ('a * language, string) PMap.t

(** A decision tree for translations. **)
type 'a tree =
  | Leaf of 'a list
    (** A leaf: the only possible translations at this stage.
     * There may be more than one: one is then taken randomly. **)
  | Node of tag * 'a tree * 'a tree
    (** When reaching this node, we divide the set of translations
     * in two subsets: the one where the tag is present (first subset)
     * and the one where is it not present (second subset). **)

(** Each translation item is associated its actual translation,
 * as well as a set of tag that has been added and a set of tag that
 * has been removed. **)
type 'a gt =
  ('a * language, (string * tag PSet.t * tag PSet.t) tree) PMap.t

type 'b sitem =
  | Direct of string
  | Variable of 'b * tag PSet.t * tag PSet.t * tag PSet.t

(** Splits the commands into a list of constraints (conserving the ordering),
 * a set of added tags, and a set of removed tags. **)
let splits_commands commands =
  let (tags, diff) =
    Utils.list_partition_map (fun (c, tag) ->
      match c with
      | None -> Utils.Left tag
      | Some b -> Utils.Right (b, tag)) commands in
  let (added, removed) =
    PSet.partition_map (fun (b, tag) ->
      if b then Utils.Left tag else Utils.Right tag) (PSet.from_list diff) in
  (tags, added, removed)

let variable x commands =
  let (tags, added, removed) = splits_commands commands in
  Variable (x, PSet.from_list tags, added, removed)

(** Similar to type [gt], the first set is the set of added tags and the second
 * of removed tags. **)
type ('a, 'b) st =
  ('a * language, ('b sitem list * tag PSet.t * tag PSet.t) tree) PMap.t

type translation_function = tag PSet.t -> (string * tag PSet.t) option
type complete_translation_function = tag PSet.t -> string * tag PSet.t

type element = {
    category : Id.t t ;
    attribute : State.attribute t ;
    constructor : State.constructor gt ;
    add : (State.constructor * language, tag PSet.t) PMap.t
  }


let empty = PMap.empty
let gempty = PMap.empty
let sempty = PMap.empty

let empty_element = {
    category = empty ;
    attribute = empty ;
    constructor = gempty ;
    add = PMap.empty
  }


let add m lg o str = PMap.add (o, lg) str m

let translate m lg o =
  try Some (PMap.find (o, lg) m)
  with Not_found -> None

(** Produces a [force_] alternative to a translation function by trying
 * the [generic] language if the given one failed.
 * It also takes as an argument a return with an empty string and a way
 * to map each strings in a result. **)
let fallback_to_generic lg f d change =
  match f lg with
  | Some r -> r
  | None ->
    match f generic with
    | Some r -> change (fun str -> "<" ^ str ^ ">") r
    | None ->
      change (fun str ->
        let str = if str = "" then "" else (" (" ^ str ^ ")") in
        "<Missing translation" ^ str ^ ">") d

let force_translate m lg o =
  fallback_to_generic lg (fun lg -> translate m lg o) "" Utils.id


(** Given a set of tags and a tree, explores the tree following the path
 * indicated by the set.
 * It then returns the found list. **)
let rec naive_search_tree tags = function
  | Leaf l -> l
  | Node (t, t1, t2) ->
    if PSet.mem t tags then
      naive_search_tree tags t1
    else naive_search_tree tags t2

(** Most of the time, we absolutely want a result and we need to backtrack.
 * It is safe to return a result associated with less tags than provided.
 * This alternative function thus explores more of the set by looking at
 * negative branches (the opposite is however not safe in general).
 * More precisely, it returns two things: a list of results, and a list of
 * subtrees to look for it the first list is not satisfactory. **)
let search_tree tags =
  let rec aux ts = function
    | Leaf l -> (l, ts)
    | Node (t, t1, t2) ->
      if PSet.mem t tags then
        aux (t2 :: ts) t1
      else aux ts t2 in
  aux []

(** Given a set of tags and a function, finds the corresponding list
 * and apply the function to this list.
 * This function is given the list of tags seen when traversing the tree
 * in the order they were given. **)
let apply_tree tags f =
  let rec aux seen = function
  | Leaf l -> f (List.rev seen) l
  | Node (t, t1, t2) ->
    let (t1, t2) =
      if PSet.mem t tags then
        (aux (t :: seen) t1, t2)
      else (t1, aux (t :: seen) t2) in
    Node (t, t1, t2) in
  aux []

(** Just adds a value to the list naturally given by [naive_search_tree]. **)
let add_tree tags v =
  apply_tree tags (fun _ l -> Leaf (v :: l))

exception ConflictingCommands of command * command

let gadd m lg commands o str =
  let (tags, added, removed) = splits_commands commands in
  let t =
    try PMap.find (o, lg) m
    with Not_found -> Leaf [] in
  PMap.add (o, lg) (apply_tree (PSet.from_list tags) (fun seen l ->
    let seen = PSet.from_list seen in
    let rec aux l = function
      | [] -> Leaf ((str, added, removed) :: l)
      | tag :: tags ->
        if PSet.mem tag seen then aux l tags
        else Node (tag, aux [] tags, Leaf l) in
    aux l tags) t) m

let sadd = gadd

(** Removes and adds the requested tags. **)
let apply_patch tags added removed =
  PSet.merge added (PSet.diff tags removed)

let gtranslate m lg o tags =
  let rec aux = function
    | [] -> None
    | t :: ts ->
      let (l, ts') = search_tree tags t in
      try
        let (str, added, removed) = Utils.select_any l in
        Some (str, apply_patch tags added removed)
      with Utils.EmptyList -> aux (ts' @ ts) in
  try let t = PMap.find (o, lg) m in aux [t]
  with Not_found -> None

let gforce_translate m lg o tags =
  fallback_to_generic lg
    (fun lg -> gtranslate m lg o tags)
    (String.concat ", " (PSet.to_list tags), PSet.empty)
    (fun f (str, s) -> (f str, s))

let stranslate m lg tgv trv o tags =
  let rec aux = function
    | [] -> None
    | t :: ts ->
      let (l, ts') = search_tree tags t in
      let rec loop = function
      | (l, added, removed) :: l' ->
        (match Utils.list_map_option (function
               | Direct str -> Some str
               | Variable (x, constrs, added, removed) ->
                 let tags = apply_patch (tgv x) added removed in
                 Utils.if_option (trv x tags) (fun (tr, tags) ->
                   if PSet.incl constrs tags then
                     Some tr
                   else None)) l with
        | Some l ->
          Some (String.concat "" l, apply_patch tags added removed)
        | None -> loop l')
      | [] -> aux (ts' @ ts) in
      loop (Utils.shuffle l) in
  try let t = PMap.find (o, lg) m in aux [t]
  with Not_found -> None

let sforce_translate m lg tgv trv o tags =
  fallback_to_generic lg
    (fun lg -> stranslate m lg tgv trv o tags)
    (String.concat ", " (PSet.to_list tags), PSet.empty)
    (fun f (str, s) -> (f str, s))


let from_json fileName fileContent =
  match Yojson.Safe.from_string ~fname:fileName fileContent with
  | `List l ->
    Utils.list_fold_lefti (fun i (t, lgs) ->
        let current =
          "The " ^ string_of_int (1 + i) ^ "th element"
          ^ " of the file `" ^ fileName ^ "'" in function
        | `Assoc l ->
          let errorKey key =
            failwith (current ^ " associates the field `" ^ key
                      ^ "' to something else than a string.") in
          let lg =
            try match List.assoc "iso639" l with
                | `String lg -> lg
                | _ -> errorKey "iso639"
            with Not_found ->
              failwith (current ^ " has no key `iso639'.") in
          (List.fold_left (fun t -> function
            | key, `String str -> add t lg key str
            | (key, _) -> errorKey key) t l, lg :: lgs)
        | _ ->
          failwith (current ^ " is not an object.")) (empty, []) l
  | _ -> failwith ("The file `" ^ fileName ^ "' is not a list.")

