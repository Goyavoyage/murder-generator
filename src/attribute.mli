(** Module Attribute
 * Describes the player and contact attributes used thorough this development. **)

(** A signature for the various attribute/constructor structures.
 * This signature is used in particular for the player attributes and the contact
 * attributes. **)
module type Attribute = sig

    (** The type of attributes. **)
    type attribute

    (** The type of constructors. **)
    type constructor

    (** Values are just constructor identifiers.
     * Each attribute is associated with a given set of possible constructors
     * (which are really just names).
     * The following table keeps track of the constructor names. **)
    type constructor_map

    (** An empty constructor map. **)
    val empty_constructor_map : constructor_map

    (** Returns the name of an attribute. **)
    val attribute_name : constructor_map -> attribute -> string option

    (** Returns the name of a constructor. **)
    val constructor_name : constructor_map -> constructor -> string option

    (** Returns the associated attribute of a constructor. **)
    val constructor_attribute : constructor_map -> constructor -> attribute option

    (** Returns the list of constructors associated to an attribute. **)
    val constructors : constructor_map -> attribute -> constructor list option

    (** Declare an attribute, returning its associated normal identifier
     * (if already declared, its previously-set identifier is still returned). **)
    val declare_attribute : constructor_map -> string -> attribute * constructor_map

    (** Declare a new constructor for an attribute.
     * (if already declared, its previously-set identifier is still returned). **)
    val declare_constructor : constructor_map -> attribute -> string -> constructor * constructor_map

    (** Get the attribute identifier from its name. **)
    val get_attribute : constructor_map -> string -> attribute option

    (** Get the constructor identifier from its attribute and its name. **)
    val get_constructor : constructor_map -> attribute -> string -> constructor option

    (** Users can remove categories before the story generation.
     * This function removes a constructor, probably because it was associated
     * to an unwanted category. **)
    val remove_constructor : constructor_map -> constructor -> constructor_map

    (** States that the first constructor is compatible with the second. **)
    val declare_compatibility : constructor_map -> attribute -> constructor -> constructor -> constructor_map

    (** States whether the first constructor is compatible with the second. **)
    val is_compatible : constructor_map -> attribute -> constructor -> constructor -> bool

  end

(** A module to express attributes and constructors for players. **)
module PlayerAttribute : Attribute

(** A module to express attributes and constructors for contacts between players. **)
module ContactAttribute : Attribute

(** This data structure stores all the informations about constructors. **)
type constructor_maps = {
    player : PlayerAttribute.constructor_map ;
    contact : ContactAttribute.constructor_map
  }

(** An empty structure. **)
val empty_constructor_maps : constructor_maps

(** A generic attribute type for modules who don’t need to precisely
 * understand how attributes work, merging both kinds of attributes. **)
type attribute =
  | PlayerAttribute of PlayerAttribute.attribute
  | ContactAttribute of ContactAttribute.attribute

(** Similarly, a generic constructor type. **)
type constructor =
  | PlayerConstructor of PlayerAttribute.constructor
  | ContactConstructor of ContactAttribute.constructor

