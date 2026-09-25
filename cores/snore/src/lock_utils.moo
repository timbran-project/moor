object LOCK_UTILS [
  import_export_id -> "lock_utils"
]
  name: "lock utilities"
  parent: GENERIC_UTILS
  owner: #2
  readable: true

  property index_incremented (owner: #2, flags: "rc") = 0;
  property input_index (owner: #2, flags: "rc") = 0;
  property input_length (owner: #2, flags: "rc") = 0;
  property input_string (owner: #2, flags: "rc") = "";
  property player (owner: #2, flags: "rc") = 0;

  override aliases (owner: #2, flags: "rc") = {"lock utilities"};
  override description (owner: #2, flags: "rc") = "This the lock utilities package, used by the MOOwide locking mechanisms. See `help $lock_utils' for more details.";
  override help_msg (owner: #2, flags: "rc") = {
    "These routines are used when locking objects, and when testing an object's lock before allowing use (such as in an exit).",
    "",
    ":parse_keyexp   (string keyexpression, object player)",
    "        => returns an object or list for the new key as defined by the",
    "           keyexpression or a string describing the error if it failed.",
    "",
    ":eval_key       (LIST|OBJ key, testobject)",
    "        => returns true if the given testobject satisfies the key.",
    "",
    ":unparse_key    (LIST|OBJ key)",
    "        => returns a string describing the key in english/moo-code terms.",
    "",
    "For more information on keys and locking, read `help locking', `help keys', and `help @lock'."
  };
  override object_size (owner: HACKER, flags: "r") = {9664, 1084848672};

  method init_scanner owner: #2
    "Initialize the shared lock-expression scanner for one uninterrupted parse.";
    this.input_string = args[1];
    this.input_length = length(args[1]);
    this.input_index = 1;
    this.index_incremented = 0;
  endmethod

  method scan_token owner: #2
    "Read the next lock token and advance the scanner; return an empty string at end.";
    const string = this.input_string;
    const len = this.input_length;
    let i = this.input_index;
    while (i <= len && string[i] == " ")
      i = i + 1;
    endwhile
    if (i > len)
      this.index_incremented = 0;
      return "";
    endif
    let ch = string[i];
    if (ch in {"(", ")", "!", "?"})
      this.input_index = i + 1;
      this.index_incremented = 1;
      return ch;
    elseif (ch in {"&", "|"})
      this.input_index = i = i + 1;
      this.index_incremented = 1;
      if (i <= len && string[i] == ch)
        this.input_index = i + 1;
        this.index_incremented = 2;
      endif
      return ch + ch;
    else
      const start = i;
      while (true)
        if (i <= len)
          ch = string[i];
        endif
        if (!(i <= len && !(ch in {"(", ")", "!", "?", "&", "|"})))
          break;
        endif
        i = i + 1;
      endwhile
      this.input_index = i;
      i = i - 1;
      while (string[i] == " ")
        i = i - 1;
      endwhile
      this.index_incremented = i - start + 1;
      return this:canonicalize_spaces(string[start..i]);
    endif
  endmethod

  method canonicalize_spaces owner: #2
    "Collapse repeated spaces in an object name.";
    let name = args[1];
    while (index(name, "  "))
      name = strsub(name, "  ", " ");
    endwhile
    return name;
  endmethod

  method parse_keyexp owner: #2
    "parse_keyexp(STRING keyexpression, OBJ player) => returns a list containing the coded key, or a string containing an error message if the attempt failed.";
    "";
    "Grammar for key expressions:";
    "";
    "    E ::= A       ";
    "       |  E || A  ";
    "       |  E && A  ";
    "    A ::= ( E )   ";
    "       |  ! A     ";
    "       |  object  ";
    "       |  ? object  ";
    this:init_scanner(args[1]);
    this.player = args[2];
    return this:parse_E();
  endmethod

  method parse_E owner: #2
    "Parse a lock expression, retaining left-to-right logical grouping.";
    let exp = this:parse_A();
    if (typeof(exp) != TYPE_STR)
      while (true)
        const token = this:scan_token();
        if (!(token in {"&&", "||"}))
          break;
        endif
        const rhs = this:parse_A();
        typeof(rhs) == TYPE_STR && return rhs;
        exp = {token, exp, rhs};
      endwhile
      "The while loop above always eats a token. Reset it back so the iteration can find it again. Always losing `)'. Ho_Yan 3/9/95";
      this.input_index = this.input_index - this.index_incremented;
    endif
    return exp;
  endmethod

  method parse_A owner: #2
    "Parse a lock atom, parenthesized expression, or negation.";
    let exp;
    const token = this:scan_token();
    if (token == "(")
      exp = this:parse_E();
      typeof(exp) != TYPE_STR && this:scan_token() != ")" && return "Missing ')'";
      return exp;
    elseif (token == "!")
      exp = this:parse_A();
      typeof(exp) == TYPE_STR && return exp;
      return {"!", exp};
    elseif (token == "?")
      const next = this:scan_token();
      if (next in {"(", ")", "!", "&&", "||", "?"})
        return "Missing object-name before '" + token + "'";
      endif
      next == "" && return "Missing object-name at end of key expression";
      const what = this:match_object(next);
      typeof(what) == TYPE_OBJ && return {"?", this:match_object(next)};
      return what;
    elseif (token in {"&&", "||"})
      return "Missing expression before '" + token + "'";
    elseif (token == "")
      return "Missing expression at end of key expression";
    else
      return this:match_object(token);
    endif
  endmethod

  method eval_key owner: #2
    "eval_key(LIST|OBJ coded key, OBJ testobject) => returns true if testobject will solve the provided key.";
    const {key, who} = args;
    const type = typeof(key);
    !(type in {TYPE_LIST, TYPE_OBJ}) && return true;
    typeof(key) == TYPE_OBJ && return who == key || $object_utils:contains(who, key);
    const op = key[1];
    op == "!" && return !this:eval_key(key[2], who);
    if (op == "?")
      return key[2]:is_unlocked_for(who);
    elseif (op == "&&")
      return this:eval_key(key[2], who) && this:eval_key(key[3], who);
    elseif (op == "||")
      return this:eval_key(key[2], who) || this:eval_key(key[3], who);
    else
      raise(E_DIV);
    endif
  endmethod

  method match_object owner: #2
    "used by $lock_utils to unparse a key expression so one can use `here' and `me' as well as doing the regular object matching.";
    const token = args[1];
    token == "me" && return this.player;
    if (token == "here")
      valid(this.player.location) && return this.player.location;
      return "'here' has no meaning where " + this.player.name + " is";
    else
      const what = this.player.location:match_object(token);
      what == $failed_match && return "Can't find an object named '" + token + "'";
      what == $ambiguous_match && return "Multiple objects named '" + token + "'";
      return what;
    endif
  endmethod

  method unparse_key owner: #2
    ":unparse_key(LIST|OBJ coded key) => returns a string describing the key in english/moo-code terms.";
    "Example:";
    "$lock_utils:unparse_key({\"||\", $hacker, $housekeeper}) => \"#18105[Hacker] || #36830[housekeeper]\"";
    let exp;
    const key = args[1];
    const type = typeof(key);
    !(type in {TYPE_LIST, TYPE_OBJ}) && return "(None.)";
    if (type == TYPE_OBJ)
      valid(key) && return tostr(key, "[", key.name, "]");
      return tostr(key);
    else
      const op = key[1];
      const arg1 = this:unparse_key(key[2]);
      op == "?" && return "?" + arg1;
      if (op == "!")
        typeof(key[2]) == TYPE_LIST && return "!(" + arg1 + ")";
        return "!" + arg1;
      elseif (op in {"&&", "||"})
        const other = op == "&&" ? "||" | "&&";
        const lhs = arg1;
        const rhs = this:unparse_key(key[3]);
        if (typeof(key[2]) == TYPE_OBJ || key[2][1] != other)
          exp = lhs;
        else
          exp = "(" + lhs + ")";
        endif
        exp = exp + " " + op + " ";
        if (typeof(key[3]) == TYPE_OBJ || key[3][1] != other)
          exp = exp + rhs;
        else
          exp = exp + "(" + rhs + ")";
        endif
        return exp;
      else
        raise(E_DIV);
      endif
    endif
  endmethod

  method eval_key_new owner: #2
    "Evaluate an extended lock with unprivileged authority.";
    set_task_perms($no_one);
    const {key, who} = args;
    const type = typeof(key);
    !(type in {TYPE_LIST, TYPE_OBJ}) && return true;
    typeof(key) == TYPE_OBJ && return who == key || $object_utils:contains(who, key);
    const op = key[1];
    op == "!" && return !this:eval_key(key[2], who);
    if (op == "?")
      return key[2]:is_unlocked_for(who);
    elseif (op == "&&")
      return this:eval_key(key[2], who) && this:eval_key(key[3], who);
    elseif (op == "||")
      return this:eval_key(key[2], who) || this:eval_key(key[3], who);
    elseif (op == ".")
      $object_utils:has_property(who, key[2]) && who.(key[2]) && return true;
      for thing in ($object_utils:all_contents(who))
        $object_utils:has_property(thing, key[2]) && thing.(key[2]) && return true;
      endfor
      return false;
    elseif (op == ":")
      $object_utils:has_verb(who, key[2]) && who:(key[2])() && return true;
      for thing in ($object_utils:all_contents(who))
        $object_utils:has_verb(thing, key[2]) && thing:(key[2])() && return true;
      endfor
      return false;
    else
      raise(E_DIV);
    endif
  endmethod

  method parse_A_new owner: #2
    "Parse an extended lock atom including method-based predicates.";
    let exp;
    let next;
    const token = this:scan_token();
    if (token == "(")
      exp = this:parse_E();
      typeof(exp) != TYPE_STR && this:scan_token() != ")" && return "Missing ')'";
      return exp;
    elseif (token == "!")
      exp = this:parse_A();
      typeof(exp) == TYPE_STR && return exp;
      return {"!", exp};
    elseif (token == "?")
      next = this:scan_token();
      if (next in {":", ".", "(", ")", "!", "&&", "||", "?"})
        return "Missing object-name before '" + token + "'";
      endif
      next == "" && return "Missing object-name at end of key expression";
      const what = this:match_object(next);
      typeof(what) == TYPE_OBJ && return {"?", this:match_object(next)};
      return what;
    elseif (token in {":", "."})
      next = this:scan_token();
      if (next in {":", ".", "(", ")", "!", "&&", "||", "?"})
        return "Missing verb-or-property-name before '" + token + "'";
      endif
      if (next == "")
        return "Missing verb-or-property-name at end of key expression";
      elseif (typeof(next) != TYPE_STR)
        return "Non-string verb-or-property-name at end of key expression";
      else
        return {token, next};
      endif
    elseif (token in {"&&", "||"})
      return "Missing expression before '" + token + "'";
    elseif (token == "")
      return "Missing expression at end of key expression";
    else
      return this:match_object(token);
    endif
  endmethod
endobject
