object PRONOUNS
  name: "Pronoun System"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  property he_him (owner: HACKER, flags: "r") = <#28, .verb_be = "is", .verb_have = "has", .display = "he/him", .ps = "he", .po = "him", .pp = "his", .pq = "his", .pr = "himself", .is_plural = false>;
  property it_its (owner: HACKER, flags: "r") = <#28, .verb_be = "is", .verb_have = "has", .display = "it/its", .ps = "it", .po = "it", .pp = "its", .pq = "its", .pr = "itself", .is_plural = false>;
  property she_her (owner: HACKER, flags: "r") = <#28, .verb_be = "is", .verb_have = "has", .display = "she/her", .ps = "she", .po = "her", .pp = "her", .pq = "hers", .pr = "herself", .is_plural = false>;
  property spivak (owner: HACKER, flags: "r") = <#28, .verb_be = "is", .verb_have = "has", .display = "e/em", .ps = "e", .po = "em", .pp = "eir", .pq = "eirs", .pr = "emself", .is_plural = false>;
  property they_them (owner: HACKER, flags: "r") = <#28, .verb_be = "are", .verb_have = "have", .display = "they/them", .ps = "they", .po = "them", .pp = "their", .pq = "theirs", .pr = "themselves", .is_plural = true>;

  override description = "Pronoun system providing preset and custom pronoun sets for objects and players.";
  override import_export_id = "pronouns";

  verb mk (this none this) owner: HACKER flags: "rxd"
    "Create a custom pronoun set as a flyweight.";
    "Usage: $pronouns:mk(subject, object, possessive_adj, possessive_noun, reflexive [, is_plural])";
    "Example: $pronouns:mk(\"ze\", \"zir\", \"zir\", \"zirs\", \"zirself\")";
    {ps, po, pp, pq, pr, ?is_plural = false} = args;
    typeof(ps) == STR || raise(E_TYPE, "All pronoun arguments must be strings");
    typeof(po) == STR || raise(E_TYPE, "All pronoun arguments must be strings");
    typeof(pp) == STR || raise(E_TYPE, "All pronoun arguments must be strings");
    typeof(pq) == STR || raise(E_TYPE, "All pronoun arguments must be strings");
    typeof(pr) == STR || raise(E_TYPE, "All pronoun arguments must be strings");
    verb_be = is_plural ? "are" | "is";
    verb_have = is_plural ? "have" | "has";
    display = ps + "/" + po;
    return <this, .display = display, .ps = ps, .po = po, .pp = pp, .pq = pq, .pr = pr, .is_plural = is_plural, .verb_be = verb_be, .verb_have = verb_have>;
  endverb

  verb display (this none this) owner: HACKER flags: "rxd"
    "Display pronouns in common format like 'they/them' or 'it/its'.";
    "Can be called on preset or custom flyweight.";
    {pronoun_set} = args;
    typeof(pronoun_set) == FLYWEIGHT || raise(E_TYPE, "Argument must be a pronoun flyweight");
    try
      return pronoun_set.display;
    except (E_PROPNF)
      return pronoun_set.ps + "/" + pronoun_set.po;
    endtry
  endverb

  verb lookup (this none this) owner: HACKER flags: "rxd"
    "Look up a pronoun set by display name like 'they/them' or 'he/him'.";
    "Returns the pronoun object if found, or false if not found.";
    {search} = args;
    search = search:trim();
    !search && return false;
    target = search:lowercase();
    "Check each preset by comparing display property";
    presets = {this.he_him, this.she_her, this.they_them, this.it_its, this.spivak};
    for preset in (presets)
      display = this:display(preset);
      if (display == search || display:lowercase() == target)
        return preset;
      endif
    endfor
    return false;
  endverb

  verb list_presets (this none this) owner: HACKER flags: "rxd"
    "Return a list of available preset pronoun display names.";
    presets = {this.he_him, this.she_her, this.they_them, this.it_its, this.spivak};
    return { this:display(p) for p in (presets) };
  endverb
endobject