object PRONOUNS_HE_HIM
  name: "he/him"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  property display (owner: HACKER, flags: "r") = "he/him";
  property is_plural (owner: HACKER, flags: "r") = false;
  property po (owner: HACKER, flags: "r") = "him";
  property pp (owner: HACKER, flags: "r") = "his";
  property pq (owner: HACKER, flags: "r") = "his";
  property pr (owner: HACKER, flags: "r") = "himself";
  property ps (owner: HACKER, flags: "r") = "he";
  property verb_be (owner: HACKER, flags: "r") = "is";
  property verb_have (owner: HACKER, flags: "r") = "has";

  override description = "Pronoun set: he/him/his.";
  override import_export_id = "pronouns_he_him";
endobject