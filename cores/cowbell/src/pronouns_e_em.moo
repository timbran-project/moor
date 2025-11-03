object PRONOUNS_E_EM
  name: "e/em"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  property display (owner: HACKER, flags: "r") = "e/em";
  property is_plural (owner: HACKER, flags: "r") = false;
  property po (owner: HACKER, flags: "r") = "em";
  property pp (owner: HACKER, flags: "r") = "eir";
  property pq (owner: HACKER, flags: "r") = "eirs";
  property pr (owner: HACKER, flags: "r") = "emself";
  property ps (owner: HACKER, flags: "r") = "e";
  property verb_be (owner: HACKER, flags: "r") = "is";
  property verb_have (owner: HACKER, flags: "r") = "has";

  override description = "Pronoun set: e/em/eir (Spivak).";
  override import_export_id = "pronouns_e_em";
endobject