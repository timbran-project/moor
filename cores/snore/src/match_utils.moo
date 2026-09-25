object MATCH_UTILS [
  import_export_id -> "match_utils"
]
  name: "matching utilities"
  parent: GENERIC_UTILS
  owner: HACKER
  readable: true

  property matching_room (owner: HACKER, flags: "r") = #-1;
  property ordinal_regexp (owner: HACKER, flags: "rc") = "%<%(first%|second%|third%|fourth%|fifth%|sixth%|seventh%|eighth%|ninth%|tenth%|1st%|2nd%|3rd%|4th%|5th%|6th%|7th%|8th%|9th%|10th%)%>";
  property ordn (owner: HACKER, flags: "rc") = {
    "first",
    "second",
    "third",
    "fourth",
    "fifth",
    "sixth",
    "seventh",
    "eighth",
    "ninth",
    "tenth"
  };
  property ordw (owner: HACKER, flags: "rc") = {"1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th", "10th"};

  override aliases (owner: HACKER, flags: "rc") = {"matching utilities"};
  override help_msg (owner: HACKER, flags: "rc") = {
    "$match_utils defines the following verbs:",
    "",
    "match",
    "match_nth",
    "match_verb",
    "match_list",
    "parse_ordinal_reference (alias parse_ordref)",
    "parse_possessive_reference",
    "object_match_failed",
    "",
    "For more documentation, see help $match_utils:<specific verb>."
  };
  override object_size (owner: HACKER, flags: "r") = {9401, 1084848672};

  method match owner: HACKER
    ":match(string, object-list)";
    "Return object in 'object-list' aliased to 'string'.";
    "Matches on a wide variety of syntax, including:";
    " \"5th axe\" -- The fifth object matching \"axe\" in the object list.";
    " \"where's sai\" -- The only object contained in 'where' matching \"sai\" (possible $ambiguous_match).";
    " \"where's second staff\" -- The second object contained in 'where' matching \"staff\".";
    " \"my third dagger\" -- The third object in your inventory matching \"dagger\".";
    "Ordinal matches are determined according to the match's position in 'object-list' or, if a possessive (such as \"where\" above) is given, then the ordinal is the nth match in that object's inventory.";
    "In the matching room (#3879@LambdaMOO), the 'object-list' consists of first the player's contents, then the room's, and finally all exits leading from the room.";
    let object;
    let parsed;
    const {string, olist} = args;
    !string && return $nothing;
    if (string == "me")
      return player;
    elseif (string == "here")
      return player.location;
    else
      object = $string_utils:literal_object(string);
      valid(object) && return object;
      object = $string_utils:match(string, olist, "aliases");
      valid(object) && return object;
      parsed = this:parse_ordinal_reference(string);
      parsed && return this:match_nth(parsed[2], olist, parsed[1]);
      parsed = this:parse_possessive_reference(string);
      if (parsed)
        const {whostr, objstr} = parsed;
        const whose = this:match(whostr, olist);
        valid(whose) && return this:match(objstr, whose.contents);
        return whose;
      else
        return object;
      endif
    endif
    "Profane (#30788) - Sat Jan  3, 1998 - Changed so literals get returned ONLY if in the passed object list.";
    "Profane (#30788) - Sat Jan  3, 1998 - OK, that broke lots of stuff, so changed it back.";
  endmethod

  method match_nth owner: HACKER
    ":match_nth(string, objlist, n)";
    "Find the nth object in 'objlist' that matches 'string'.";
    let what;
    let where;
    let n;
    {what, where, n} = args;
    for v in (where)
      let z = 0;
      for q in (v.aliases)
        z = z || index(q, what) == 1;
      endfor
      if (z)
        n = n - 1;
      endif
      if (z && !n)
        return v;
      endif
    endfor
    return $failed_match;
  endmethod

  method match_verb owner: #2
    "$match_utils:match_verb(verbname, object) => Looks for a command-line style verb named <verbname> on <object> with current values of prepstr, dobjstr, dobj, iobjstr, and iobj.  If a match is made, the verb is called with @args[3] as arguments and 1 is returned.  Otherwise, 0 is returned.";
    const {vrb, what, rest} = args;
    const where = $object_utils:has_verb(what, vrb);
    if (where)
      const vargs = verb_args(where[1], vrb);
      if (vargs != {"this", "none", "this"})
        if (vargs[2] == "any" || (!prepstr && vargs[2] == "none") || index("/" + vargs[2] + "/", "/" + prepstr + "/") && (vargs[1] == "any" || (!dobjstr && vargs[1] == "none") || (dobj == what && vargs[1] == "this")) && (vargs[3] == "any" || (!iobjstr && vargs[3] == "none") || (iobj == what && vargs[3] == "this")) && index(verb_info(where[1], vrb)[2], "x") && verb_code(where[1], vrb))
          set_task_perms(caller_perms());
          what:(vrb)(@rest);
          return 1;
        endif
      endif
    endif
  endmethod

  method match_list owner: HACKER
    ":match_list(string, object_list) -> List of all matches.";
    let what;
    let where;
    {what, where} = args;
    !what && return {};
    let r = {};
    for v in (where)
      if (!(v in r))
        let z = 0;
        for q in (v.aliases)
          z = z || (q && index(q, what) == 1);
        endfor
        if (z)
          "r = listappend(r, v);";
          r = {@r, v};
        endif
      endif
    endfor
    return r;
    "Hydros (#106189) - Sun Jul 3, 2005 - Changed listappend to a splice to save ticks. Old code commented above.";
  endmethod

  method "parse_ordinal_reference parse_ordref" owner: HACKER
    ":parse_ordref(string)";
    "Parses strings referring to an 'nth' object.";
    "=> {INT n, STR object} Where 'n' is the number the ordinal represents, and 'object' is the rest of the string.";
    "=> 0 If the given string is not an ordinal reference.";
    "  Example:";
    ":parse_ordref(\"second broadsword\") => {2, \"broadsword\"}";
    ":parse_ordref(\"second\") => 0";
    "  Note that there must be more to the string than the ordinal alone.";
    const m = match(args[1], "^" + this.ordinal_regexp + " +%([^ ].+%)$");
    if (m)
      const o = substitute("%1", m);
      const n = o in this.ordn || o in this.ordw;
      return n && {n, substitute("%2", m)};
    else
      return 0;
    endif
  endmethod

  method parse_possessive_reference owner: HACKER
    ":parse_possessive_reference(string)";
    "Parses strings in a possessive format.";
    "=> {STR whose, STR object}  Where 'whose' is the possessor of 'object'.";
    "If the string consists only of a possessive string (ie: \"my\", or \"yduJ's\"), then 'object' will be an empty string.";
    "=> 0 If the given string is not a possessive reference.";
    "  Example:";
    ":parse_possessive_reference(\"joe's cat\") => {\"joe\", \"cat\"}";
    ":parse_possessive_reference(\"sis' fish\") => {\"sis\", \"fish\"}";
    "  Strings are returned as a value suitable for a :match routine, thus 'my' becoming 'me'.";
    ":parse_possessive_reference(\"my dog\") => {\"me\", \"dog\"}";
    const string = args[1];
    let m = match(string, "^my$%|^my +%(.+%)?");
    m && return {"me", substitute("%1", m)};
    m = match(string, "^%(.+s?%)'s? *%(.+%)?");
    m && return {substitute("%1", m), substitute("%2", m)};
    return 0;
    "Profane (#30788) - Sun Jun 21, 1998 - changed first parenthetical match bit from %([^ ]+s?%) to %(.+s?%)";
  endmethod

  method object_match_failed owner: HACKER
    "Usage: object_match_failed(object, string[, ambigs])";
    "Prints a message if string does not match object.  Generally used after object is derived from a :match_object(string).";
    "ambigs is an optional list of the objects that were matched upon.  If given, the message printed will list the ambiguous among them as choices.";
    let {match_result, string, ?ambigs = 0} = args;
    const tell = 0 && $perm_utils:controls(caller_perms(), player) ? "notify" | "tell";
    if (index(string, "#") == 1 && $code_utils:toobj(string) != E_TYPE)
      "...avoid the `I don't know which `#-2' you mean' message...";
      if (!valid(match_result))
        player:(tell)(tostr("There is no \"", string, "\" that you can see."));
      endif
      return !valid(match_result);
    endif
    if (match_result == $nothing)
      player:(tell)("You must give the name of some object.");
    elseif (match_result == $failed_match)
      player:(tell)(tostr("There is no \"", string, "\" that you can see."));
    elseif (match_result == $ambiguous_match)
      if (typeof(ambigs) != TYPE_LIST)
        player:(tell)(tostr("I don't know which \"", string, "\" you mean."));
        return 1;
      endif
      ambigs = $match_utils:match_list(string, ambigs);
      ambigs = $list_utils:map_property(ambigs, "name");
      if (length($list_utils:remove_duplicates(ambigs)) == 1 && $object_utils:isa(player.location, this.matching_room))
        player:(tell)(tostr("I don't know which \"", string, "\" you mean.  Try using \"first ", string, "\", \"second ", string, "\", etc."));
      else
        player:(tell)(tostr("I don't know which \"", string, "\" you mean: ", $string_utils:english_list(ambigs, "nothing", " or "), "."));
      endif
      return 1;
    elseif (!valid(match_result))
      player:(tell)(tostr("The object you specified does not exist.  Seeing ghosts?"));
    else
      return 0;
    endif
    return 1;
  endmethod

  method init_for_core owner: #2
    "Reset this object for an extracted core. Wizard callers only.";
    if (caller_perms().wizard)
      pass(@args);
      this.matching_room = $nothing;
    endif
  endmethod
endobject
