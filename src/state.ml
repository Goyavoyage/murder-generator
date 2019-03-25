
type character = Utils.Id.t

type objective = {
    difficulty : int ;
    complexity : int
  }

type relation_state =
  Relation.t array array * objective array

let copy_relation_state (r, o) =
  (Array.map Array.copy r, Array.copy o)

exception SelfRelation

let zero_objective = {
    difficulty = 0 ;
    complexity = 0
  }

(** Relation states have as little cells as possible: [n - 1] for the
 * first counter, and [i + 1] for the second.
 * To get the relation between characters [c1] and [c2], with [c1 < c2],
 * one has to check the array at [.(c2 - 1).(c1)]. **)
let create_relation_state n =
  (Array.init (n - 1) (fun i ->
     Array.make (i + 1) Relation.neutral),
   Array.make n zero_objective)

let rec read_relation_state (a, _) c1 c2 =
  let c1 = Utils.Id.to_array c1 in
  let c2 = Utils.Id.to_array c2 in
  if c1 = c2 then Relation.neutral
  else if c2 > c1 then
    a.(c2 - 1).(c1)
  else Relation.reverse a.(c1 - 1).(c2)

let write_relation_state (a, rs) c1 c2 r =
  let c1 = Utils.Id.to_array c1 in
  let c2 = Utils.Id.to_array c2 in
  let (x, y, r) =
    if c1 = c2 then
      raise SelfRelation
    else if c2 > c1 then
      (c2 - 1, c1, r)
    else (c1 - 1, c2, Relation.reverse r) in
  let old = a.(x).(y) in
  a.(x).(y) <- r ;
  let dd = Relation.difficulty r - Relation.difficulty old in
  let dc = Relation.complexity r - Relation.complexity old in
  rs.(c1) <- {
      difficulty = rs.(c1).difficulty + dd ;
      complexity = rs.(c1).complexity + dc
    } ;
  rs.(c2) <- {
      difficulty = rs.(c2).difficulty + dd ;
      complexity = rs.(c2).complexity + dc
    }

let add_relation_state a c1 c2 r =
  (** As [Relation.neutral] is neutral for [Relation.compose] and that it
   * happens frequently, we first check whether we really need to update
   * anything. **)
  if r <> Relation.neutral then
    let r' = read_relation_state a c1 c2 in
    write_relation_state a c1 c2 (Relation.compose r' r)

let character_complexity (_, r) c =
  r.(Utils.Id.to_array c).complexity

let character_difficulty (_, r) c =
  r.(Utils.Id.to_array c).difficulty

let set_complexity (_, r) c v =
  r.(Utils.Id.to_array c) <- { r.(Utils.Id.to_array c) with complexity = v }

let set_difficulty (_, r) c v =
  r.(Utils.Id.to_array c) <- { r.(Utils.Id.to_array c) with difficulty = v }

let add_complexity (_, r) c d =
  let o = r.(Utils.Id.to_array c) in
  r.(Utils.Id.to_array c) <- { o with complexity = d + o.complexity }

let add_difficulty (_, r) c d =
  let o = r.(Utils.Id.to_array c) in
  r.(Utils.Id.to_array c) <- { o with difficulty = d + o.difficulty }

module type Attribute = sig
    type attribute
    type constructor
    type constructor_map

    val empty_constructor_map : constructor_map
    val attribute_name : constructor_map -> attribute -> string option
    val constructor_name : constructor_map -> constructor -> string option
    val constructor_attribute : constructor_map -> constructor -> attribute option
    val constructors : constructor_map -> attribute -> constructor list option
    val declare_attribute : constructor_map -> string -> attribute * constructor_map
    val declare_constructor : constructor_map -> attribute -> string -> constructor * constructor_map
    val get_attribute : constructor_map -> string -> attribute option
    val get_constructor : constructor_map -> attribute -> string -> constructor option
    val remove_constructor : constructor_map -> constructor -> constructor_map
    val declare_compatibility : constructor_map -> attribute -> constructor -> constructor -> constructor_map
    val is_compatible : constructor_map -> attribute -> constructor -> constructor -> bool
  end

module AttributeInst () =
  struct

    type attribute = Utils.Id.t
    type constructor = Utils.Id.t

    type constructor_map =
      string Utils.Id.map (** Attribute names **)
      * (attribute * string) Utils.Id.map
          (** The map storing each constructor.
           * The attribute is part of the constructor,
           * with the constructor name. **)
      * (attribute, constructor list) PMap.t
          (** Which constructors is associated to which attribute. **)
      * (attribute, (constructor, constructor list) PMap.t) PMap.t
          (** For each constructor, what are its compatibility list. **)

    let empty_constructor_map =
      (Utils.Id.map_create (),
       Utils.Id.map_create (),
       PMap.empty,
       PMap.empty)

    let attribute_name (m, _, _, _) a =
      Utils.Id.map_inverse m a

    let constructor_name (_, m, _, _) c =
      Option.map snd (Utils.Id.map_inverse m c)

    let constructor_attribute (_, m, _, _) c =
      Option.map fst (Utils.Id.map_inverse m c)

    let constructors (_, _, m, _) a =
      try Some (PMap.find a m)
      with Not_found -> None

    let declare_attribute (mn, mc, al, comp) a =
      let (a, mn) = Utils.Id.map_insert_t mn a in
      (a, (mn, mc, (if PMap.mem a al then al else PMap.add a [] al), comp))

    let declare_constructor (mn, mc, al, comp) a c =
      let (c, mc) = Utils.Id.map_insert_t mc (a, c) in
      let l =
        try PMap.find a al
        with Not_found -> assert false in
      (c, (mn, mc, PMap.add a (c :: l) al, comp))

    let get_attribute (mn, _, _, _) a =
      Utils.Id.get_id mn a

    let get_constructor (_, mc, _, _) a c =
      Utils.Id.get_id mc (a, c)

    let remove_constructor m c =
      let a = Utils.assert_option __LOC__ (constructor_attribute m c) in
      let (mn, mc, al, comp) = m in
      let filter = List.filter ((<>) c) in
      let l =
        try PMap.find a al
        with Not_found -> assert false in
      let comp =
        let m =
          try PMap.find a comp
          with Not_found -> PMap.empty in
        let m =
          List.fold_left (fun m c ->
            let l =
              try PMap.find c m
              with Not_found -> [] in
            PMap.add c (filter l) m) m l in
        PMap.add a (PMap.remove c m) comp in
      (mn, mc, PMap.add a (filter l) al, comp)

    let declare_compatibility (mn, mc, al, comp) a c c' =
      let m =
        try PMap.find a comp
        with Not_found -> PMap.empty in
      let l =
        try PMap.find c m
        with Not_found -> [] in
      (mn, mc, al, PMap.add a (PMap.add c (c' :: l) m) comp)

    let is_compatible (_, _, _, comp) a c c' =
      let m =
        try PMap.find a comp
        with Not_found -> PMap.empty in
      let l =
        try PMap.find c m
        with Not_found -> [] in
      List.mem c' l

  end

module PlayerAttribute = AttributeInst ()

module ContactAttribute = AttributeInst ()

type constructor_maps = {
    player : PlayerAttribute.constructor_map ;
    contact : ContactAttribute.constructor_map
  }

let empty_constructor_maps = {
    player = PlayerAttribute.empty_constructor_map ;
    contact = ContactAttribute.empty_constructor_map
  }

type attribute =
  | PlayerAttribute of PlayerAttribute.attribute
  | ContactAttribute of ContactAttribute.attribute

type constructor =
  | PlayerConstructor of PlayerAttribute.constructor
  | ContactConstructor of ContactAttribute.constructor

type strictness =
  | NonStrict
  | LowStrict
  | Strict

let compose_strictness s1 s2 =
  match s1, s2 with
  | Strict, _ | _, Strict -> None
  | LowStrict, LowStrict -> None
  | NonStrict, s | s, NonStrict -> Some s

type 'value attribute_value =
  | Fixed_value of 'value list * strictness
  | One_value_of of 'value list

let compose_attribute_value compatible v1 v2 =
  let compatible v1 v2 = v1 = v2 || compatible v1 v2 in
  match v1, v2 with
  | One_value_of l1, One_value_of l2 ->
    let l3 = List.filter (fun v -> List.mem v l1) l2 in
    if l3 = [] then None else Some (One_value_of l3)
  | One_value_of l1, Fixed_value (l2, s2) | Fixed_value (l2, s2), One_value_of l1 ->
    let l = List.filter (fun v2 -> List.mem v2 l1) l2 in
    if l <> [] then Some (Fixed_value (l, s2)) else None
  | Fixed_value (l1, s1), Fixed_value (l2, s2) ->
    Utils.if_option (compose_strictness s1 s2) (fun s3 ->
      let l3 =
        let aux low non =
          List.filter (fun v ->
            List.exists (fun v' -> compatible v' v) non) low in
        match s1, s2 with
        | LowStrict, NonStrict -> aux l1 l2
        | NonStrict, LowStrict -> aux l2 l1
        | NonStrict, NonStrict ->
          Utils.list_map_filter (fun v ->
            try Some (ExtList.List.find_map (fun v' ->
                        if compatible v' v then Some v
                        else if compatible v v' then Some v'
                        else None) l2)
            with Not_found -> None) l1
        | _ -> assert false in
      if l3 <> [] then
        Some (Fixed_value (l3, s3))
      else None)

let attribute_value_progress v1 v2 =
  match v1, v2 with
  | One_value_of _, Fixed_value _ -> true
  | One_value_of l1, One_value_of l2 -> List.length l1 > List.length l2
  | Fixed_value (l1, _), Fixed_value (l2, _) -> List.length l1 > List.length l2
  | _, _ -> false

let attribute_value_can_progress = function
  | One_value_of l -> l <> []
  | Fixed_value (_, _) -> false

type attribute_map =
  (PlayerAttribute.attribute, PlayerAttribute.constructor attribute_value) PMap.t
type contact_map =
  (character, (ContactAttribute.attribute,
    ContactAttribute.constructor attribute_value) PMap.t) PMap.t

type character_state =
  (attribute_map * contact_map) array

let create_character_state n =
  Array.init n (fun i -> (PMap.empty, PMap.empty))

let get_all_attributes_character st c =
  fst st.(Utils.Id.to_array c)

let get_attribute_character st c a =
  try Some (PMap.find a (get_all_attributes_character st c))
  with Not_found -> None

let write_attribute_character st c a v =
  let c = Utils.Id.to_array c in
  st.(c) <- (PMap.add a v (fst st.(c)), snd st.(c))

let force_get_attribute_character cm st c a =
  match get_attribute_character st c a with
  | Some v -> v
  | None ->
    let l = Utils.assert_option __LOC__ (PlayerAttribute.constructors cm a) in
    let v = One_value_of l in
    write_attribute_character st c a v ;
    v

let get_contact_character st c a ct =
  try Some (PMap.find a (PMap.find ct (snd st.(Utils.Id.to_array c))))
  with Not_found -> None

let write_contact_character st c a ct v =
  let c = Utils.Id.to_array c in
  let m =
    try PMap.find ct (snd st.(c))
    with Not_found -> PMap.empty in
  let m = PMap.add a v m in
  st.(c) <- (fst st.(c), PMap.add ct m (snd st.(c)))

let get_all_contact_character st c ct =
  Utils.pmap_to_list (
    try PMap.find ct (snd st.(Utils.Id.to_array c))
    with Not_found -> PMap.empty)

let get_all_contacts_character st c =
  PMap.map Utils.pmap_to_list (snd st.(Utils.Id.to_array c))

type t =
  character_state * relation_state * History.state

let copy (st, a, h) =
  (Array.copy st, copy_relation_state a, History.copy h)

let get_relation_state (_, a, _) = a

let read_relation st = read_relation_state (get_relation_state st)

let write_relation st = write_relation_state (get_relation_state st)
let add_relation st = add_relation_state (get_relation_state st)

let create_state n =
  (create_character_state n, create_relation_state n, History.create_state n)

let get_character_state (st, _, _) = st

(** Creates a list of characters from the total number of characters. **)
let all_players_length l =
  List.map Utils.Id.from_array (Utils.seq l)

let number_of_player (st, _, _) = Array.length st

let all_players st =
  all_players_length (number_of_player st)

let number_of_player_relation_state (_, rs) = Array.length rs

let all_players_relation st =
  all_players_length (number_of_player_relation_state st)

