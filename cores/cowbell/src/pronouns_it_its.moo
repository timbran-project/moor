object PRONOUNS_IT_ITS
  name: "it/its"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  property display (owner: HACKER, flags: "r") = "it/its";
  property is_plural (owner: HACKER, flags: "r") = false;
  property po (owner: HACKER, flags: "r") = "it";
  property pp (owner: HACKER, flags: "r") = "its";
  property pq (owner: HACKER, flags: "r") = "its";
  property pr (owner: HACKER, flags: "r") = "itself";
  property ps (owner: HACKER, flags: "r") = "it";
  property verb_be (owner: HACKER, flags: "r") = "is";
  property verb_have (owner: HACKER, flags: "r") = "has";

  override description = "Pronoun set: it/its.";
  override import_export_id = "pronouns_it_its";
endobject