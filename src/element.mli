(** Module Element
 * Data structure and functions about story elements. **)

type character = State.character

(** A constraint on a character **)
type character_constraint =
  | Attribute of State.PlayerAttribute.attribute
                 * State.PlayerAttribute.constructor State.attribute_value
    (** The given attribute value is provided by the element.
      * Note that [State.attribute_constructor] can be of the form
      * [State.One_value_of], in which case the attribute is required to be of
      * this value, but also [State.Fixed_value], where the element actually
      * provides an explanation for it. **)
  | Contact of State.ContactAttribute.attribute
               * int
               * State.ContactAttribute.constructor State.attribute_value
    (** The given contact (identified in the local array) is provided by the
     * element. **)

type t =
  ((** Each players considered by the element are represented as a cell. **)
   character_constraint list (** The constraints on this player. **)
   * History.event list (** The events that this element would provide to
                         * this player. **)
   * Relation.t array (** The relations that would be added to this player,
                       * for each characters.
                       * This array can be less than the number of players
                       * in this element ([Neutral] is then assumed for all
                       * other cells). **)
  ) array

(** Returns the list of attribute that an element may provide. **)
val provided_attributes : t -> State.attribute list

(** Given a state, an element, and an instantiation of the characters, states
 * whether the event can be applied.
 * If not, it returns [None].
 * If the element can be applied, it states whether the element is making
 * progress, that is whether there exists at least one attribute value that
 * has been changed to something recognised by [State.attribute_value_progress]. **)
val compatible_and_progress : State.t -> t -> character array -> bool option

(** Look for instantiations.
 * The second return value is the result of [compatible_and_progress] on this instantiation.
 * It tries to return an instantiation that progresses. **)
val search_instantiation : State.t -> t -> (character array * bool) option

(** Apply the given element to the state according to this instantiation.
 * This application is not functional (although the new state is returned,
 * invalidating the previous one).
 * This function should only be applied to instantiations for which
 * [compatible_and_progress] returns [Some].
 * It also provides the difference of attributes that have been fixed with the ones
 * that have been created, as a number for each attribute.
 * For instance, if an instantiation defines an attribute [a] that was to be defined
 * (that is, for which [State.attribute_value_can_progress] returned true),
 * it will associate [1] to [a]; if it adds an attribute to be defined, it will
 * associate [-1] instead.
 * Once the total number of attribute to be defined is zero, the state can be published. **)
val apply : State.t -> t -> character array -> State.t * (State.attribute, int) PMap.t

(** Get the resulting relation array from an instantiation.
 * The input state is not modified by this function. **)
val apply_relations : State.relation_state -> t -> character array -> State.relation_state

