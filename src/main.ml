(** Module Main.
 * This file is the one compiled to JavaScript, then fetched and executed
 * to run the whole program. **)

open ExtList
open ExtString


(** This entire file is parameterised by an interface as specified in the
 * InOut Module. **)
module Main (IO : InOut.T) = struct

let webpage_link = "https://github.com/Mbodin/murder-generator"
let webpage_issues = "https://github.com/Mbodin/murder-generator/issues"


(** The default error messages. **)
let errorTranslationsDefault =
  ("An error occurred!", "Please report it", "there", "Error details:")

(** The translations needed to print error messages. **)
let errorTranslations = ref errorTranslationsDefault

(** Getting and parsing the translations file. **)
let get_translations _ =
  let%lwt (translation, languages) =
    let translations_file = "web/translations.json" in
    let%lwt translations = IO.get_file translations_file in
    Lwt.return (Translation.from_json translations_file translations) in
  (** Shuffling languages, but putting the user languages on top. **)
  let (matching, nonmatching) =
    List.partition (fun lg ->
      let lg = Translation.iso639 lg in
      List.exists (fun ulg -> String.exists ulg lg) IO.languages) languages in
  Lwt.return (translation, Utils.shuffle matching @ Utils.shuffle nonmatching)

(** Prints a list of strings, [andw] being the word for “and”
 * in the current language.
 * This function makes use of the Oxford comma. **)
let print_list andw = function
  | [] -> "none"
  | a :: [] -> a
  | a :: b :: [] -> a ^ " " ^ andw ^ " " ^ b
  | l ->
    let (l, r) = Utils.assert_option __LOC__ (Utils.list_match_right l) in
    String.concat ", " l ^ ", " ^ andw ^ " " ^ r

(** Get and parse each data file. **)
let get_data _ =
  let intermediate = ref Driver.empty_intermediary in
  Lwt_list.iter_p (fun fileName ->
      let%lwt file = IO.get_file fileName in
      let lexbuf = Lexing.from_string file in
      let file = Driver.parse_lexbuf fileName lexbuf in
      intermediate := Driver.prepare_declarations !intermediate file ;
      Lwt.return ())
    MurderFiles.files ;%lwt
  if not (Driver.is_intermediary_final !intermediate) then (
    let categories = Driver.categories_to_be_defined !intermediate in
    let (attributes, contacts) = Driver.attributes_to_be_defined !intermediate in
    let (player_constructors, contact_constructors) =
      Driver.constructors_to_be_defined !intermediate in
    let player_constructors =
      PSet.map (fun (a, c) -> c ^ " (" ^ a ^ ")") player_constructors in
    let contact_constructors =
      PSet.map (fun (a, c) -> c ^ " (" ^ a ^ ")") contact_constructors in
    let tags = Driver.tags_to_be_defined !intermediate in
    let tags = PSet.map (fun (lg, tag) -> lg ^ ":" ^ tag) tags in
    let events = Driver.events_to_be_defined !intermediate in
    let missing str s =
      " Missing " ^ str ^ ": " ^ print_list "and" (PSet.to_list s) ^ "." in
    Lwt.fail (Invalid_argument
      ("Non final intermediary after parsing all files."
       ^ missing "categories" categories
       ^ missing "attributes" attributes
       ^ missing "contacts" contacts
       ^ missing "attributes constructors" player_constructors
       ^ missing "contacts contacts" contact_constructors
       ^ missing "events" events
       ^ missing "language tags" tags)))
  else Lwt.return (Driver.parse !intermediate)

(** A type to store what each page of the menu provides. **)
type parameters = {
    language : Translation.language option ;
    player_number : int ;
    general_level : float ;
    general_complexity : float ;
    play_date : Date.t ;
    computation_power : float ;
    categories : Id.t PSet.t option ;
    player_information : (string (** Character name *)
                          * int (** Complexity **)
                          * int (** Difficulty **)
                          * Attribute.PlayerAttribute.constructor list
                              (** Preset attributes **)) list ;
    chosen_productions : string PSet.t (** The name of each chosen production. **)
  }

(** The main script. **)
let main =
  try%lwt
    IO.clear_response () ;
    let%lwt (translation, languages) = get_translations () in
    let get_translation_language lg key =
      Utils.assert_option ("No key `" ^ key ^ "' found for language `"
                           ^ (Translation.iso639 lg) ^ "' at " ^ __LOC__ ^ ".")
        (Translation.translate translation lg key) in
    let get_language p = Utils.assert_option __LOC__ p.language in
    let get_translation p = get_translation_language (get_language p) in
    (** Adds a “next” and “previous” buttons and call them when needed.
     * This function waits for the user to either click on the previous or
     * next button, then calls the function to get the parameters, and
     * finally calls the appropriate function.
     * Both functions are given as option-types: if [None] is given, the
     * corresponding button doesn’t appear.
     * The text (more precisely, its key) for each button can be changed. **)
    let next_button ?(previousText = "previous") ?(nextText = "next")
        w p get_parameters previous next =
      let jump f _ =
        IO.clear_response () ;
        Lwt.wakeup_later w (fun _ -> f (get_parameters ())) in
      let createListButton dir text f =
        match f with
        | None -> []
        | Some f ->
          [ InOut.LinkContinuation (dir, get_translation p text, jump f) ] in
      let previous = createListButton false previousText previous in
      let next = createListButton true nextText next in
      IO.print_block (InOut.Div (InOut.Centered,
        if previous = [] || next = [] then previous @ next
        else previous @ [ InOut.Space ] @ next)) in
    (** We request the data without forcing it yet. **)
    let data = get_data () in
    let rec ask_for_languages parameters =
      errorTranslations := errorTranslationsDefault ;
      (** Showing to the user all available languages. **)
      let%lwt language =
        let (res, w) = Lwt.task () in
        IO.print_block (InOut.Div (InOut.Normal, List.map (fun lg ->
          let get_translation = get_translation_language lg in
          InOut.Div (InOut.Centered, [
            InOut.P [ InOut.LinkContinuation (true, get_translation "name",
              fun _ ->
                IO.clear_response () ;
                errorTranslations :=
                  (get_translation "error", get_translation "report",
                   get_translation "there", get_translation "errorDetails") ;
                Lwt.wakeup_later w lg) ]])) languages)) ;
        IO.stopLoading () ;%lwt
        res in
      load_or_create { parameters with language = Some language }
    and load_or_create parameters =
      let get_translation = get_translation parameters in
      let (cont, w) = Lwt.task () in
      (** Describing the project to the user. **)
      IO.print_block (InOut.P [
          InOut.Text (get_translation "description") ;
          InOut.Text (get_translation "openSource") ;
          InOut.Link (get_translation "there", webpage_link)
        ]) ;
      (** Start a new scenario. **)
      IO.print_block (InOut.P [
          InOut.Text (get_translation "createNewScenario") ;
          InOut.LinkContinuation (true, get_translation "startGeneration",
            fun _ ->
              Lwt.wakeup_later w (fun _ ->
                IO.clear_response () ;
                ask_for_basic parameters)) ]) ;
      (** Suggest to shortcut the generation by importing a file. **)
      let (shortcut, readShortcut) =
        IO.createFileImport ["json"] (fun _ ->
          IO.clear_response () ;
          IO.startLoading ()) in
      IO.print_block (InOut.Div (InOut.Normal, [
          InOut.P [ InOut.Text (get_translation "importFileShortcut") ] ;
          InOut.Div (InOut.Centered, [
              InOut.Node shortcut ;
              InOut.LinkContinuation (true, get_translation "shortcutGeneration",
                fun _ ->
                  Lwt.wakeup_later w (fun _ ->
                    let%lwt (fileName, str) = readShortcut () in
                    if fileName = "" && str = "" then (
                      IO.print_block ~error:true (InOut.P [
                        InOut.Text (get_translation "noFileSelected") ]) ;
                      IO.stopLoading () ;%lwt
                      load_or_create parameters
                    ) else (
                      let%lwt data = data in
                      let (names, state) =
                        Export.from_json (Driver.get_import_information data)
                          fileName str in
                      let informations =
                        List.mapi (fun c name ->
                          let c = Id.from_array c in
                          let st = State.get_relation_state state in
                          (name, State.character_complexity st c,
                           State.character_difficulty st c,
                           [] (* TODO: Get them from the state. *))) names in
                      let parameters =
                        { parameters with
                            player_information = informations ;
                            categories =
                              Some (PSet.from_list
                                      (Driver.all_categories data)) } in
                      chooseFormats (Lwt.return state) parameters
                    )))
            ])
        ])) ;
      next_button ~nextText:"startGeneration" w parameters (fun _ -> parameters)
        (Some ask_for_languages) (Some ask_for_basic) ;
      let%lwt cont = cont in cont ()
    and ask_for_basic parameters =
      let get_translation = get_translation parameters in
      let (cont, w) = Lwt.task () in
      (** Asking the first basic questions about the murder party. **)
      let (playerNumber, readPlayerNumber) =
        IO.createNumberInput ~min:1 parameters.player_number in
      IO.print_block (InOut.P [
          InOut.Text (get_translation "howManyPlayers") ;
          InOut.Node playerNumber
        ]) ;
      let (generalLevel, readGeneralLevel) =
        IO.createPercentageInput parameters.general_level in
      IO.print_block (InOut.Div (InOut.Normal, [
          InOut.P [ InOut.Text (get_translation "experience") ] ;
          InOut.Div (InOut.Centered, [
              InOut.Text (get_translation "beginner") ;
              InOut.Node generalLevel ;
              InOut.Text (get_translation "experienced")
            ])
        ])) ;
      let (generalComplexity, readGeneralComplexity) =
        IO.createPercentageInput parameters.general_complexity in
      IO.print_block (InOut.Div (InOut.Normal, [
          InOut.P [ InOut.Text (get_translation "lengthOfCharacterSheets") ] ;
          InOut.Div (InOut.Centered, [
              InOut.Text (get_translation "shortSheets") ;
              InOut.Node generalComplexity ;
              InOut.Text (get_translation "longSheets")
            ])
        ])) ;
      let (playDate, readPlayDate) =
        IO.createDateInput parameters.play_date in
      IO.print_block (InOut.P [
          InOut.Text (get_translation "whenDoYouPlanToPlay") ;
          InOut.Node playDate
        ]) ;
      let (fastOrSlow, readFastOrSlow) =
        IO.createPercentageInput parameters.computation_power in
      IO.print_block (InOut.Div (InOut.Normal, [
          InOut.P [ InOut.Text (get_translation "fastOrSlowGeneration") ] ;
          InOut.Div (InOut.Centered, [
              InOut.Text (get_translation "fastGeneration") ;
              InOut.Node fastOrSlow ;
              InOut.Text (get_translation "slowGeneration")
            ])
        ])) ;
      next_button w parameters (fun _ ->
          { parameters with
              player_number = readPlayerNumber () ;
              general_level = readGeneralLevel () ;
              general_complexity = readGeneralComplexity () ;
              play_date = readPlayDate () ;
              computation_power = readFastOrSlow () })
        (Some load_or_create) (Some ask_for_categories) ;
      let%lwt cont = cont in cont ()
    and ask_for_categories parameters =
      let get_translation = get_translation parameters in
      let (cont, w) = Lwt.task () in
      (** Forcing the data to be loaded. **)
      (if Lwt.state data = Lwt.Sleep then
        IO.startLoading ()
      else Lwt.return ()) ;%lwt
      let%lwt data = data in
      IO.stopLoading () ;%lwt
      (** Asking about categories. **)
      let translate_categories =
        let translate_categories =
          (Driver.get_translations data).Translation.category in
        Translation.force_translate translate_categories
          (get_language parameters) in
      let all_categories = Driver.all_categories data in
      let selected_categories =
        match parameters.categories with
        | None -> PSet.from_list all_categories
        | Some s -> s in
      let onCategoryClick = ref (fun _ -> ()) in
      let categoriesButtons =
        List.fold_left (fun m c ->
          let dependencies =
            let deps =
              List.map translate_categories (PSet.to_list
                (Driver.get_category_dependencies data c)) in
            if deps = [] then None
            else
              Some ("(" ^ get_translation "categoryDepends" ^ " "
                    ^ print_list (get_translation "and") deps ^ ")") in
          let (e, set, get) =
            IO.createSwitch (translate_categories c)
              None dependencies (PSet.mem c selected_categories)
              (fun _ -> !onCategoryClick c) in
          PMap.add c (e, set, get, PSet.empty) m) PMap.empty all_categories in
      let categoriesButtons =
        List.fold_left (fun m c ->
            let deps = Driver.get_category_dependencies data c in
            PSet.fold (fun cd m ->
              let (e, set, get, ideps) = PMap.find cd m in
              PMap.add cd (e, set, get, PSet.add c ideps) m) m deps)
          categoriesButtons all_categories in
      onCategoryClick := (fun c ->
        let (_, _, get, ideps) = PMap.find c categoriesButtons in
        if get () then
          let deps = Driver.get_category_dependencies data c in
          PSet.iter (fun c ->
            let (_, set, _, _) = PMap.find c categoriesButtons in
            set true) deps
        else
          PSet.iter (fun c ->
            let (_, set, _, _) = PMap.find c categoriesButtons in
            set false) ideps) ;
      IO.print_block (InOut.Div (InOut.Normal, [
          InOut.P [ InOut.Text (get_translation "unselectCategories") ] ;
          InOut.Div (InOut.Centered, [
              InOut.LinkContinuation (false, get_translation "noCategories",
                fun _ ->
                  PMap.iter (fun _ (_, set, _, _) -> set false) categoriesButtons) ;
              InOut.Space ;
              InOut.LinkContinuation (true, get_translation "allCategories",
                fun _ ->
                  PMap.iter (fun _ (_, set, _, _) -> set true) categoriesButtons) ;
            ]) ;
          InOut.List (false,
            PMap.fold (fun (e, _, _, _) l -> InOut.Node e :: l)
              categoriesButtons [])
        ])) ;
      next_button w parameters (fun _ ->
          let selected_categories =
            PMap.foldi (fun c (_, _, get, _) s ->
              if get () then
                PSet.add c s
              else s) categoriesButtons PSet.empty in
          { parameters with categories = Some selected_categories })
        (Some ask_for_basic) (Some ask_for_player_constraints) ;
      let%lwt cont = cont in cont ()
    and ask_for_player_constraints parameters =
      let get_translation = get_translation parameters in
      let%lwt data = data in
      let (cont, w) = Lwt.task () in
      let player_number = parameters.player_number in
      (** Asking about individual player constraints. **)
      IO.print_block (InOut.Div (InOut.Normal, [
        InOut.P [ InOut.Text (get_translation "individualConstraints") ] ;
        InOut.P [ InOut.Text (get_translation "complexityDifficultyExplanation") ] ;
        InOut.List (true, [
            InOut.Text (get_translation "lowComplexityLowDifficulty") ;
            InOut.Text (get_translation "lowComplexityHighDifficulty") ;
            InOut.Text (get_translation "highComplexityLowDifficulty") ;
            InOut.Text (get_translation "highComplexityHighDifficulty") ])])) ;
      let startV = get_translation "nameStartVowels" in
      let startC = get_translation "nameStartConsonant" in
      let middleV = get_translation "nameMiddleVowels" in
      let middleC = get_translation "nameMiddleConsonant" in
      let endV = get_translation "nameEndVowels" in
      let endC = get_translation "nameEndConsonant" in
      let size =
        let raw = get_translation "nameSize" in
        try int_of_string raw
        with Failure _ ->
          failwith ("The key `nameSize' for language `" ^
                    (Translation.iso639 (get_language parameters)) ^ "' is `" ^ raw
                    ^ "', which is not a valid number.") in
      let seed =
        Names.createVowelConsonant size startV startC middleV middleC endV endC in
      let player_information =
        let (complexity, difficulty) =
          let generalLevel = parameters.general_level in
          let generalComplexity = parameters.general_complexity in
          let generalLevel = generalLevel *. generalLevel in
          let complexityDifficulty =
            10. +. generalLevel *. 90. in
          let result p = int_of_float (0.5 +. complexityDifficulty *. p) in
          (result generalComplexity, result (1. -. generalComplexity)) in
          let player_information = parameters.player_information in
          let len = List.length player_information in
        if len >= player_number then
          List.take player_number player_information
        else
          List.fold_left (fun player_information _ ->
              let name =
                (** Because the seed contains external data, one can hardly
                 * assume that it can produce infinitely many different names.
                 * We are thus stuck to just generate new ones until a really new
                 * one appears. **)
                let rec aux = function
                  | 0 -> Names.generate seed
                  | n ->
                    let name = Names.generate seed in
                    if List.exists (fun (name', _, _, _) ->
                         name' = name) player_information then
                      aux (n - 1)
                    else name in
                aux 100 in
              (name, complexity, difficulty, []) :: player_information)
            player_information (Utils.seq (player_number - len)) in
      let constructor_maps = Driver.get_constructor_maps data in
      let translation = Driver.get_translations data in
      let constructor_infos c =
        let m = constructor_maps.Attribute.player in
        let a =
          Utils.assert_option __LOC__
            (Attribute.PlayerAttribute.constructor_attribute m c) in
        let name =
          let an =
            Utils.assert_option __LOC__
              (Attribute.PlayerAttribute.attribute_name m a) in
          let cn =
            Utils.assert_option __LOC__
              (Attribute.PlayerAttribute.constructor_name m c) in
          an ^ ": " ^ cn in
        let translated =
          Translation.force_translate translation.Translation.attribute
            (get_language parameters) (Attribute.PlayerAttribute a) ^ ": "
          ^ fst (Translation.gforce_translate translation.Translation.constructor
                  (get_language parameters) (Attribute.PlayerConstructor c)
                  (PSet.singleton Translation.base)) in
        (a, Attribute.PlayerAttribute.is_internal m a c, name, translated) in
      let (internal_cons, main_cons) =
        let categories = Utils.assert_option __LOC__ parameters.categories in
        let all_constructors =
          Utils.list_map_filter (fun c ->
            let dep =
              Driver.get_constructor_dependencies data
                (Attribute.PlayerConstructor c) in
            if PSet.incl dep categories then
              Some (c, constructor_infos c)
            else None) (Attribute.PlayerAttribute.all_constructors
                         constructor_maps.Attribute.player) in
        Utils.list_partition_map (fun (c, (a, internal, n, t)) ->
          let r = (c, a, n, t) in
          if internal then Utils.Left r else Utils.Right r) all_constructors in
      let table =
        List.map (fun (name, complexity, difficulty, misc) ->
          (IO.createTextInput name,
           IO.createNumberInput complexity,
           IO.createNumberInput difficulty,
           let getrec =
             (* This reference is frustrating: I could not find another way to make
              * the compiler accept the recursion in this case. *)
             ref (fun _ -> assert false) in
           let (node, get) =
             let proposed =
               try let (_, _, _, t) = Utils.select_any main_cons in t
               with Utils.EmptyList -> "" in
             let misc =
               List.map (fun c ->
                 let (a, _, _, t) = constructor_infos c in
                 (t, (a, c))) misc in
             IO.createResponsiveListInput misc proposed (fun txt ->
               let re = Re.Str.regexp_string_case_fold txt in
               let corresponds txt' =
                 try Some (Re.Str.search_forward re txt' 0)
                 with Not_found -> None in
               let already_chosen =
                 PSet.from_list (List.map (fun (a, _) -> a) (!getrec ())) in
               let num_shown = 10 in
               let get_from_list l =
                 let l =
                   Utils.list_map_filter (fun (c, a, n, t) ->
                     if PSet.mem a already_chosen then None
                     else
                       let d =
                         match corresponds t with
                         | Some d -> Some (true, d)
                         | None ->
                           Option.map (fun d -> (false, d)) (corresponds n) in
                       Option.map (fun d -> (c, a, d, t)) d) l in
                 let l =
                   List.sort ~cmp:(fun (_, _, (t1, d1), _) (_, _, (t2, d2), _) ->
                     if t1 && not t2 then -1
                     else if t2 && not t1 then 1
                     else compare d1 d2) l in
                 Utils.list_header num_shown l in
               let l =
                 Utils.list_header num_shown
                   (get_from_list main_cons @ get_from_list internal_cons) in
               List.map (fun (c, a, _, t) -> (t, (a, c))) l) in
           getrec := get ;
           (node, get))) player_information in
      IO.print_block (InOut.Div (InOut.Normal, [
        InOut.P [ InOut.Text (get_translation "changeThisTable") ] ;
        InOut.Div (InOut.Centered, [
          InOut.Table (["table"],
                       [(InOut.Text (get_translation "playerName"), InOut.default) ;
                        (InOut.Text (get_translation "complexity"), InOut.default) ;
                        (InOut.Text (get_translation "difficulty"), InOut.default) ;
                        (InOut.Text (get_translation "miscellaneous"),
                         InOut.default)],
                       List.map (fun ((name, _), (complexity, _),
                                      (difficulty, _), (misc, _)) -> ([], [
                           (InOut.Node name, InOut.default) ;
                           (InOut.Node complexity, InOut.default) ;
                           (InOut.Node difficulty, InOut.default) ;
                           (InOut.Node misc, InOut.default)
                         ])) table) ])])) ;
      next_button ~nextText:"startGeneration" w parameters (fun _ ->
        { parameters with
            player_information =
              List.map (fun ((_, get_name), (_, get_complexity),
                             (_, get_difficulty), (_, get_misc)) ->
                (get_name (), get_complexity (),
                 get_difficulty (), List.map snd (get_misc ()))) table
        }) (Some ask_for_categories) (Some generate) ;
      let%lwt cont = cont in cont ()
    and generate parameters =
      (** Starts the generation! **)
      let state =
        IO.pause () ;%lwt
        let%lwt data = data in
        let categories = Utils.assert_option __LOC__ parameters.categories in
        let global =
          let elements_map = Driver.elements data in
          let elements =
            Driver.get_all_elements data categories parameters.player_number in
          let elements =
            List.map (fun e -> PMap.find e elements_map) elements in
          List.fold_left Solver.register_element
            (Solver.empty_global parameters.computation_power) elements in
        let objectives =
          Array.of_list (List.map (fun (_, complexity, difficulty, _) -> {
              State.complexity = complexity ;
              State.difficulty = difficulty
            }) parameters.player_information) in
        let state = State.create_state parameters.player_number in
        let (state, diff) =
          let diff = Element.empty_difference in
          Utils.assert_option __LOC__
            (Utils.list_fold_lefti (fun i stdiff (_, _, _, attributes) ->
                Utils.if_option stdiff (fun (state, diff) ->
                  Utils.apply_option
                    (Element.apply_constructors (Driver.get_constructor_maps data)
                      state (Id.from_array i) attributes)
                    (fun (state, diff') ->
                      (state, Element.merge_attribute_differences diff diff'))))
              (Some (state, diff)) parameters.player_information) in
        Solver.solve_with_difference IO.pause global state diff objectives in
      chooseFormats state parameters
    and chooseFormats state parameters =
      IO.stopLoading () ;%lwt
      let get_translation = get_translation parameters in
      let (cont, w) = Lwt.task () in
      if Lwt.state state = Lwt.Sleep then
        IO.print_block (InOut.P [
          InOut.Text (get_translation "backgroundGeneration") ;
          InOut.Link (get_translation "there", webpage_link) ]) ;
      let exportButtons =
        List.map (fun (name, descr) ->
            let (node, set, get) =
              IO.createSwitch (get_translation "generateAs"
                                  ^ " " ^ get_translation name) None None
                (PSet.mem name parameters.chosen_productions) Utils.id in
            let node =
              InOut.Div (InOut.Inlined, [
                InOut.Node node ;
                InOut.Text (get_translation descr) ]) in
            (name, node, set, get))
          (("html", "htmlDescription")
           :: List.map (fun (name, descr, _, _, _, _) -> (name, descr))
                Export.all_production) in
      IO.print_block (InOut.Div (InOut.Normal, [
          InOut.P [ InOut.Text (get_translation "exportPossibilities") ] ;
          InOut.List (false,
            List.map (fun (_, node, _, _) -> node) exportButtons)
        ])) ;
      let check cont parameters =
        if PSet.is_empty parameters.chosen_productions then (
          IO.print_block ~error:true (InOut.P [
            InOut.Text (get_translation "noProductionSelected") ]) ;
          chooseFormats state parameters
        ) else (
          IO.startLoading () ;%lwt
          cont parameters
        ) in
      next_button w parameters (fun _ ->
          { parameters with chosen_productions =
              List.fold_left (fun s (name, _, _, get) ->
                if get () then PSet.add name s else s) PSet.empty exportButtons })
        (Some ask_for_player_constraints) (Some (check (display state))) ;
      let%lwt cont = cont in cont ()
    and display state parameters =
      let get_translation = get_translation parameters in
      let (cont, w) = Lwt.task () in
      let%lwt data = data in
      let%lwt state = state in
      (** Exports the generated state to various formats. **)
      let estate =
        Export.process {
          Export.language = get_language parameters ;
          Export.date = parameters.play_date ;
          Export.names =
            List.map (fun (name, _, _, _) -> name) parameters.player_information ;
          Export.translation = Driver.get_translations data ;
          Export.generic_translation = translation ;
          Export.constructor_maps = Driver.get_constructor_maps data ;
          Export.state = state
        } in
      let html = PSet.mem "html" parameters.chosen_productions in
      let chosen_productions =
        List.filter (fun (name, _, _, _, _, _) ->
            PSet.mem name parameters.chosen_productions)
          Export.all_production in
      if chosen_productions <> [] then
        IO.print_block (InOut.Div (InOut.Normal, [
            InOut.P
              (InOut.Text (get_translation "exportList")
               :: if html then [ InOut.Text (get_translation "exportedAsHTML") ]
                  else []) ;
            InOut.List (true,
            List.map (fun (name, descr, mime, ext, native, f) ->
              let fileName = "murder" ^ if ext = "" then "" else ("." ^ ext) in
              InOut.Div (InOut.Inlined, [
                  InOut.LinkFile (get_translation "downloadAs"
                                  ^ " " ^ get_translation name,
                                  fileName, mime, native, fun _ -> f estate) ;
                  InOut.Text (get_translation descr)
                ])) chosen_productions)
          ])) ;
      if html then IO.print_block (Export.to_block estate) ;
      IO.stopLoading () ;%lwt
      IO.print_block (InOut.P [
        InOut.Text (get_translation "lookingForContribution") ;
        InOut.Text (get_translation "participate") ;
        InOut.Link (get_translation "there", webpage_link) ]) ;
      next_button w parameters (fun _ -> parameters)
        (Some (chooseFormats (Lwt.return state))) None ;
      let%lwt cont = cont in cont () in
    let parameters = {
        language = None ;
        player_number = 13 ;
        general_level = 0.5 ;
        general_complexity = 0.5 ;
        play_date = Date.now ;
        computation_power = 0.5 ;
        categories = None ;
        player_information = [] ;
        chosen_productions = PSet.empty
      } in
    ask_for_languages parameters
  (** Reporting errors. **)
  with e ->
    try%lwt
      let (errorOccurred, reportIt, there, errorDetails) = !errorTranslations in
      IO.print_block ~error:true (InOut.Div (InOut.Normal, [
          InOut.P [
              InOut.Text errorOccurred ; InOut.Text reportIt ;
              InOut.Link (there, webpage_issues)
            ] ;
          InOut.P [
              InOut.Text errorDetails ;
              InOut.Text (Printexc.to_string e)
            ]
        ])) ;
      IO.stopLoading () ;%lwt
      Lwt.return ()
    with e' -> (** If there have been an error when printing the error,
                * we failback to the console. **)
      IO.log "Unfortunately, a important error happened." ;
      IO.log ("Please report it to " ^ webpage_issues) ;
      IO.log ("Primary error details: " ^ Printexc.to_string e) ;
      IO.log ("Secondary error details: " ^ Printexc.to_string e') ;
      Lwt.return ()

end

