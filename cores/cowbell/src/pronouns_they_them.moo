object PRONOUNS_THEY_THEM
  name: "they/them"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  property display (owner: HACKER, flags: "r") = "they/them";
  property is_plural (owner: HACKER, flags: "r") = true;
  property po (owner: HACKER, flags: "r") = "them";
  property pp (owner: HACKER, flags: "r") = "their";
  property pq (owner: HACKER, flags: "r") = "theirs";
  property pr (owner: HACKER, flags: "r") = "themselves";
  property ps (owner: HACKER, flags: "r") = "they";
  property verb_be (owner: HACKER, flags: "r") = "are";
  property verb_have (owner: HACKER, flags: "r") = "have";

  override description = "Pronoun set: they/them/their.";
  override import_export_id = "pronouns_they_them";
endobject