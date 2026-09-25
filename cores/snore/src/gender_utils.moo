object GENDER_UTILS [
  import_export_id -> "gender_utils"
]
  name: "gender utilities"
  parent: GENERIC_UTILS
  owner: HACKER
  readable: true

  property be (owner: HACKER, flags: "rc") = {"is", "is", "is", "is", "is", "is", "are", "am", "are", "are", "are"};
  property genders (owner: HACKER, flags: "rc") = {
    "neuter",
    "male",
    "female",
    "either",
    "Spivak",
    "splat",
    "plural",
    "egotistical",
    "royal",
    "2nd"
  };
  property have (owner: HACKER, flags: "rc") = {
    "has",
    "has",
    "has",
    "has",
    "has",
    "has",
    "have",
    "have",
    "have",
    "have",
    "have"
  };
  property is_plural (owner: HACKER, flags: "rc") = {false, false, false, false, false, false, true, true, true, true, true};
  property po (owner: HACKER, flags: "rc") = {"it", "him", "her", "him/her", "em", "h*", "them", "me", "us", "you"};
  property poc (owner: HACKER, flags: "rc") = {"It", "Him", "Her", "Him/Her", "Em", "H*", "Them", "Me", "Us", "You"};
  property pp (owner: HACKER, flags: "rc") = {"its", "his", "her", "his/her", "eir", "h*", "their", "my", "our", "your"};
  property ppc (owner: HACKER, flags: "rc") = {"Its", "His", "Her", "His/Her", "Eir", "H*", "Their", "My", "Our", "Your"};
  property pq (owner: HACKER, flags: "rc") = {
    "its",
    "his",
    "hers",
    "his/hers",
    "eirs",
    "h*s",
    "theirs",
    "mine",
    "ours",
    "yours"
  };
  property pqc (owner: HACKER, flags: "rc") = {
    "Its",
    "His",
    "Hers",
    "His/Hers",
    "Eirs",
    "H*s",
    "Theirs",
    "Mine",
    "Ours",
    "Yours"
  };
  property pr (owner: HACKER, flags: "rc") = {
    "itself",
    "himself",
    "herself",
    "(him/her)self",
    "emself",
    "h*self",
    "themselves",
    "myself",
    "ourselves",
    "yourself"
  };
  property prc (owner: HACKER, flags: "rc") = {
    "Itself",
    "Himself",
    "Herself",
    "(Him/Her)self",
    "Emself",
    "H*self",
    "Themselves",
    "Myself",
    "Ourselves",
    "Yourself"
  };
  property pronouns (owner: HACKER, flags: "rc") = {"ps", "po", "pp", "pq", "pr", "psc", "poc", "ppc", "pqc", "prc"};
  property ps (owner: HACKER, flags: "rc") = {"it", "he", "she", "s/he", "e", "*e", "they", "I", "we", "you"};
  property psc (owner: HACKER, flags: "rc") = {"It", "He", "She", "S/He", "E", "*E", "They", "I", "We", "You"};

  override aliases (owner: HACKER, flags: "rc") = {"Gender_Utilities"};
  override description (owner: HACKER, flags: "rc") = {
    "This is the gender utilities utility package.  See `help $gender_utils' for more details."
  };
  override help_msg (owner: HACKER, flags: "rc") = {
    "Defines the list of standard genders, the default pronouns for each, and routines for adding or setting pronoun properties on any gendered object.",
    "",
    "Properties:",
    "  .genders  -- list of standard genders",
    "  .pronouns -- list of pronoun properties",
    "  .ps .po .pp .pq .pr .psc .poc .ppc .pqc .prc ",
    "            -- lists of pronouns for each of the standard genders",
    "",
    "  If foo is of gender this.gender[n], ",
    "  then the default pronoun foo.p is this.p[n] ",
    "  (where p is one of ps/po/pp/pq...)",
    "",
    "Verbs:",
    "  :set(object,newgender) -- changes pronoun properties to match new gender.",
    "  :add(object[,perms[,owner]]) -- adds pronoun properties to object.",
    "",
    "  :get_pronoun     (which,object) -- return pronoun for a given object",
    "  :get_conj*ugation(verbspec,object) -- return appropriately conjugated verb"
  };
  override object_size (owner: HACKER, flags: "r") = {12822, 1084848672};

  method set owner: #2
    "Set an object's pronouns from a recognized gender; return its name or an error.";
    "Use caller authority and restore changed pronouns if a property write fails.";
    set_task_perms(caller_perms());
    const {object, gender} = args;
    this == object && return E_DIV;
    const position = $string_utils:find_prefix(gender, this.genders);
    !position && return E_NONE;
    let saved = {};
    for prop in (this.pronouns)
      let result = `object.(prop) ! ANY';
      saved = {@saved, result};
      if (typeof(result) == TYPE_STR)
        result = `object.(prop) = this.(prop)[position] ! ANY';
      endif
      if (typeof(result) != TYPE_STR)
        for index in [1..length(saved) - 1]
          object.(this.pronouns[index]) = saved[index];
        endfor
        return result;
      endif
    endfor
    return this.genders[position];
  endmethod

  method add owner: #2
    "Add missing pronoun properties with caller authority; initialize empty pronouns to neuter.";
    set_task_perms(caller_perms());
    const {object, ?flags = "rc", ?owner = object.owner} = args;
    let initialize = false;
    for prop in (this.pronouns)
      if (!$object_utils:has_property(object, prop))
        const error = `add_property(object, prop, "", {owner, flags}) ! ANY';
        if (typeof(error) == TYPE_ERR)
          player:tell("Couldn't add ", object, ".", prop, ": ", error);
          return;
        endif
      elseif (typeof(object.(prop)) != TYPE_STR)
        const error = `object.(prop) = "" ! ANY';
        if (typeof(error) == TYPE_ERR)
          player:tell("Couldn't reset ", object, ".", prop, ": ", error);
          return;
        endif
      endif
      !object.(prop) && (initialize = true);
    endfor
    if (initialize)
      const error = this:set(object, "neuter");
      typeof(error) == TYPE_ERR && player:tell("Couldn't initialize pronouns: ", error);
    endif
  endmethod

  method get_pronoun owner: HACKER
    "Return a requested pronoun, falling back to gender defaults and then $player.";
    let {key, ?object = player} = args;
    !key && return "";
    key[1] == ":" && (key = key[2..$]);
    const short = length(key) == 1 ? index("sopqrSOPQR", key, 1) | 0;
    let prop;
    if (short)
      prop = this.pronouns[short];
    else
      const search = "$1:he$1:she$1:he/she$2:him$2:him/her$3:his/her$4:hers$4:his/hers$5:himself$5:herself$5:himself/herself$";
      const position = index(search, ":" + key + "$");
      !position && return "";
      const capital = strcmp("a", key) > 0 ? 5 | 0;
      prop = this.pronouns[toint(search[position - 1]) + capital];
    endif
    !valid(object) && return $player.(prop);
    const value = `object.(prop) ! ANY';
    typeof(value) == TYPE_STR && return value;
    const gender = `object.gender ! ANY';
    const position = typeof(gender) == TYPE_STR ? gender in this.genders | 0;
    return position ? this.(prop)[position] | $player.(prop);
  endmethod

  method "get_conj*ugation" owner: HACKER
    "Choose singular/plural verb text from an object's gender; infer an omitted form.";
    const {spec, ?object = player} = args;
    !spec && return "";
    const slash = index(spec + "/", "/");
    const singular = spec[1..slash - 1];
    const plural = slash < length(spec) ? spec[slash + 1..$] | "";
    const capital = strcmp("a", slash == 1 ? plural | spec) > 0;
    const gender = valid(object) ? `object.gender ! ANY' | E_INVIND;
    const position = (typeof(gender) == TYPE_STR ? gender in this.genders | 0) || 1;
    const value = this.is_plural[position] ? plural || this:_verb_plural(singular, position) | singular || this:_verb_singular(plural, position);
    return capital ? $string_utils:capitalize(value) | value;
  endmethod

  method _verb_plural owner: HACKER
    "Infer a plural verb spelling, using the gender index for irregular verbs.";
    let r;
    const {st, idx} = args;
    typeof(st) != TYPE_STR && return E_INVARG;
    const len = length(st);
    !len && return "";
    if (len >= 3 && rindex(st, "n't") == len - 2)
      return this:_verb_plural(st[1..len - 3], idx) + "n't";
    endif
    const i = st in {"has", "is"};
    if (i)
      return this.({"have", "be"}[i])[idx];
    elseif (st == "was")
      return idx > 6 ? "were" | st;
    elseif (len <= 3 || st[len] != "s")
      return st;
    elseif (st[len - 1] != "e")
      return st[1..len - 1];
      "elseif ((r = (rindex(st, \"sses\") || rindex(st, \"zzes\"))) && (r == (len - 3)))";
    else
      r = rindex(st, "zzes");
      if (r && r == len - 3)
        return st[1..len - 3];
      elseif (st[len - 2] == "h" && index("cs", st[len - 3]) || index("ox", st[len - 2]) || st[len - 3..len - 2] == "ss")
        return st[1..len - 2];
        "washes => wash, belches => belch, boxes => box";
        "used to have || ((st[len - 2] == \"s\") && (!index(\"aeiouy\", st[len - 3])))";
        "so that <consonant>ses => <consonant>s";
        "known examples: none";
        "counterexample: browses => browse";
        "update of sorts--put in code to handle passes => pass";
      elseif (st[len - 2] == "i")
        return st[1..len - 3] + "y";
      else
        return st[1..len - 1];
      endif
    endif
  endmethod

  method _verb_singular owner: HACKER
    "Infer a singular verb spelling, using the gender index for irregular verbs.";
    const {st, ?idx = 1} = args;
    typeof(st) != TYPE_STR && return E_INVARG;
    const len = length(st);
    !len && return "";
    if (len >= 3 && rindex(st, "n't") == len - 2)
      return this:_verb_singular(st[1..len - 3], idx) + "n't";
    endif
    const i = st in {"have", "are"};
    if (i)
      return this.({"have", "be"}[i])[idx];
    elseif (st[len] == "y" && !index("aeiou", st[len - 1]))
      return st[1..len - 1] + "ies";
    elseif (index("sz", st[len]) && index("aeiou", st[len - 1]))
      return st + st[len] + "es";
    elseif (index("osx", st[len]) || (len > 1 && index("chsh", st[len - 1..len]) % 2))
      return st + "es";
    else
      return st + "s";
    endif
  endmethod

  method _do owner: HACKER
    "_do(cap,object,modifiers...)";
    let i;
    const {cap, object, modifiers} = args;
    if (!modifiers)
      typeof(object) != TYPE_OBJ && return tostr(object);
      !valid(object) && return (cap ? "N" | "n") + "othing";
      return cap ? object:titlec() | object:title();
    elseif (modifiers[1] == ".")
      i = index(modifiers[2..$], ".");
      if (i)
        i = i + 1;
      else
        i = index(modifiers, ":") || index(modifiers, "#") || index(modifiers, "!");
        if (!i)
          i = length(modifiers) + 1;
        endif
      endif
      const o = `object.(modifiers[2..i - 1]) ! ANY';
      typeof(o) == TYPE_ERR && return tostr("%(", o, ")");
      return this:_do(cap || strcmp("a", modifiers[2]) > 0, o, modifiers[i..$]);
    elseif (modifiers[1] == ":")
      typeof(object) != TYPE_OBJ && return tostr("%(", E_TYPE, ")");
      const p = this:get_pronoun(modifiers, object);
      p && return p;
      return tostr("%(", modifiers, "??)");
    elseif (modifiers[1] == "#")
      return tostr(object);
    elseif (modifiers[1] == "!")
      return this:get_conj(modifiers[2..$], object);
    else
      i = index(modifiers, ".") || index(modifiers, ":") || index(modifiers, "#") || index(modifiers, "!") || length(modifiers) + 1;
      const s = modifiers[1..i - 1];
      const j = s in {"dobj", "iobj", "this"};
      j && return this:_do(cap, {dobj, iobj, callers()[2][1]}[j], modifiers[i..$]);
      return tostr("%(", s, "??)");
    endif
  endmethod

  method pronoun_sub owner: #2
    "Experimental pronoun substitution. The official version is on $string_utils.";
    "syntax:  :pronoun_sub(text[,who])";
    "experimental version that accomodates Aladdin's style...";
    let old;
    let who;
    let k;
    let w;
    let o;
    let sub;
    set_task_perms($no_one);
    {old, ?who = player} = args;
    if (typeof(old) == TYPE_LIST)
      let plines = {};
      for line in (old)
        plines = {@plines, this:pronoun_sub(line, who)};
      endfor
      return plines;
    endif
    let new = "";
    const here = valid(who) ? who.location | $nothing;
    const objspec = "nditl";
    const objects = {who, dobj, iobj, caller, here};
    const prnspec = "sopqrSOPQR";
    const prprops = {"ps", "po", "pp", "pq", "pr", "Ps", "Po", "Pp", "Pq", "Pr"};
    let oldlen = length(old);
    while (true)
      const prcnt = index(old, "%");
      if (!(prcnt && prcnt < oldlen))
        break;
      endif
      let cp_args = {};
      let s = old[k = prcnt + 1];
      const brace = index("([{", s);
      if (brace)
        w = index(old[k + 1..oldlen], ")]}"[brace]);
        !w && return new + old;
        if (brace == 3)
          s = this:_do(0, who, old[prcnt + 2..(k = k + w) - 1]);
        else
          const p = old[prcnt + 2..(k = k + w) - 1];
          if (brace == 1)
            cp_args = {who, p};
          elseif (p[1] == "#")
            s = (o = index(objspec, p[2])) ? tostr(objects[o]) | "[" + p + "]";
          else
            o = index(objspec, p[1]);
            if (!o)
              s = "[" + p + "]";
            else
              cp_args = {objects[o], p[2..w - 1], strcmp(p[1], "a") < 0};
            endif
          endif
        endif
      else
        o = index(objspec, s);
        if (o)
          cp_args = {objects[o], "", strcmp(s, "a") < 0};
        else
          w = index(prnspec, s, 1);
          if (w)
            cp_args = {who, prprops[w]};
          elseif (s == "#")
            s = tostr(who);
          elseif (s != "%")
            s = "%" + s;
          endif
        endif
      endif
      new = new + old[1..prcnt - 1] + (!cp_args ? s | typeof(sub = $string_utils:_cap_property(@cp_args)) != TYPE_ERR ? sub | "%(" + tostr(sub) + ")");
      old = old[k + 1..oldlen];
      oldlen = oldlen - k;
    endwhile
    return new + old;
  endmethod
endobject
