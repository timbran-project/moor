object PRONOUNS_SHE_HER
  name: "she/her"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  property display (owner: HACKER, flags: "r") = "she/her";
  property is_plural (owner: HACKER, flags: "r") = false;
  property po (owner: HACKER, flags: "r") = "her";
  property pp (owner: HACKER, flags: "r") = "her";
  property pq (owner: HACKER, flags: "r") = "hers";
  property pr (owner: HACKER, flags: "r") = "herself";
  property ps (owner: HACKER, flags: "r") = "she";
  property verb_be (owner: HACKER, flags: "r") = "is";
  property verb_have (owner: HACKER, flags: "r") = "has";

  override description = "Pronoun set: she/her/hers.";
  override import_export_id = "pronouns_she_her";
endobject