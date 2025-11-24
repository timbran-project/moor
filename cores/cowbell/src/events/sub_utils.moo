object SUB_UTILS
  name: "Substitution Utilities"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Compiler and utilities for $sub template language.";
  override import_export_hierarchy = {"events"};
  override import_export_id = "sub_utils";
  override object_documentation = {
    "# $sub_utils - Template Compiler",
    "",
    "## Overview",
    "",
    "Compiles human-readable template strings into $sub flyweight content lists,",
    "and can decompile back to templates. Useful for builders creating passage messages",
    "and event content.",
    "",
    "## Template Syntax",
    "",
    "Templates are strings with `{...}` tokens that get replaced with $sub flyweights.",
    "",
    "### Bindings",
    "",
    "```",
    "{actor}       # Actor name (from context)",
    "{direction}   # Any binding name from context",
    "{passage_desc}",
    "```",
    "",
    "### Name Substitutions",
    "",
    "```",
    "{n}   # Actor name",
    "{nc}  # Capitalized actor name",
    "{d}   # Direct object",
    "{i}   # Indirect object",
    "{l}   # Location",
    "{t}   # This object",
    "```",
    "",
    "Add `c` for capitalized: `{nc}`, `{dc}`, etc.",
    "",
    "### Pronouns",
    "",
    "```",
    "{s}       # Actor subject pronoun (he/she/they)",
    "{o}       # Actor object pronoun (him/her/them)",
    "{p}       # Actor possessive adjective (his/her/their)",
    "{q}       # Actor possessive noun (his/hers/theirs)",
    "{r}       # Actor reflexive (himself/herself/themself)",
    "{s_dobj}  # Direct object pronouns (same suffixes available)",
    "{s_iobj}  # Indirect object pronouns",
    "```",
    "",
    "### Verb Conjugation",
    "",
    "```",
    "{be}         # \"are\" / \"is\"",
    "{have}       # \"have\" / \"has\"",
    "{look}       # \"look\" / \"looks\"",
    "{be_dobj}    # Conjugation for direct object",
    "{be_iobj}    # Conjugation for indirect object",
    "```",
    "",
    "### Articles",
    "",
    "```",
    "{a direction}    # Indefinite article: \"a\" or \"an\"",
    "{the direction}  # Definite article: \"the\"",
    "{a d}            # Indefinite article for direct object",
    "{the dc}         # Definite article for capitalized direct object",
    "{a i}            # Indefinite article for indirect object",
    "{The i}          # Capitalized article for indirect object",
    "```",
    "",
    "Articles can use any binding name or substitution abbreviation:",
    "- `d` / `dc` = direct object",
    "- `i` / `ic` = indirect object",
    "- `l` / `lc` = location",
    "- `t` / `tc` = this object",
    "- `n` / `nc` = actor",
    "",
    "Articles check the binding's is_proper_noun() and is_plural() properties.",
    "Returns empty if proper noun (a) or if proper noun (the).",
    "",
    "### Self-Alternation",
    "",
    "```",
    "{feel|feels}     # \"feel\" to actor, \"feels\" to others",
    "{your|their}     # \"your\" to actor, \"their\" to others",
    "```",
    "",
    "Can be nested with other substitutions:",
    "```",
    "{tired|exhausted} {get|gets} you down.",
    "# Actor: \"tired get you down.\"",
    "# Others: \"exhausted gets you down.\"",
    "```",
    "",
    "## Functions",
    "",
    "### compile(template_string) → list",
    "",
    "Parses a template string and returns a list of strings and $sub flyweights.",
    "",
    "### decompile(content_list) → string",
    "",
    "Reconstructs a template string from a compiled content list.",
    "",
    "## Examples",
    "",
    "```moo",
    "template = \"{nc} heads {the direction}.\";",
    "content = $sub_utils:compile(template);",
    "# Returns: {",
    "#   $sub:nc(),",
    "#   \" heads \",",
    "#   $sub:the('direction),",
    "#   \".\"",
    "# }",
    "```",
    ""
  };

  verb compile (this none this) owner: HACKER flags: "rxd"
    "Parse template string into list of strings and $sub flyweights.";
    {template} = args;
    typeof(template) != STR && raise(E_TYPE, "template must be string");

    content = {};
    pos = 1;
    length_str = length(template);

    while (pos <= length_str)
      "Find next token start";
      remaining = template[pos..$];
      token_start_offset = index(remaining, "{");
      if (!token_start_offset)
        "No more tokens - add rest of string";
        if (pos <= length_str)
          rest = template[pos..$];
          content = {@content, rest};
        endif
        break;
      endif
      token_start = pos + token_start_offset - 1;

      "Add text before token";
      if (token_start > pos)
        before = template[pos..token_start - 1];
        content = {@content, before};
      endif

      "Find token end";
      remaining_after_brace = template[token_start + 1..$];
      token_end_offset = index(remaining_after_brace, "}");
      if (!token_end_offset)
        raise(E_INVARG, "Unclosed brace in template at position " + token_start);
      endif
      token_end = token_start + token_end_offset;

      "Extract and parse token";
      token_content = template[token_start + 1..token_end - 1];
      fw = this:_parse_token(token_content);
      "Check if we got a flyweight - don't use truthiness check";
      if (typeof(fw) == FLYWEIGHT)
        content = {@content, fw};
      else
      endif

      pos = token_end + 1;
    endwhile

    return content;
  endverb

  verb _parse_token (this none this) owner: HACKER flags: "rxd"
    "Parse a single {token} and return corresponding $sub flyweight.";
    {token_content} = args;
    token_content = token_content:trim();

    "Check for self-alternation (contains |)";
    pipe_index = index(token_content, "|");
    if (pipe_index)
      parts = token_content:split("|");
      if (length(parts) != 2)
        raise(E_INVARG, "Self-alternation must have exactly 2 parts: " + token_content);
      endif
      for_self = parts[1]:trim();
      for_others = parts[2]:trim();
      result = $sub:self_alt(for_self, for_others);
      return result;
    endif

    "Helper to map substitution abbreviations to their full names";
    mapping = [
      'd -> 'dobj,
      'dc -> 'dobj,
      'i -> 'iobj,
      'ic -> 'iobj,
      'l -> 'location,
      'lc -> 'location,
      't -> 'this,
      'tc -> 'this,
      'n -> 'actor,
      'nc -> 'actor
    ];

    "Check for article (starts with 'a ', 'an ', or 'the ')";
    if (token_content:starts_with("a "))
      after_article = token_content[3..$]:trim();
      binding_name = tosym(after_article);
      result = $sub:a(binding_name);
      return result;
    elseif (token_content:starts_with("an "))
      after_article = token_content[4..$]:trim();
      binding_name = tosym(after_article);
      result = $sub:a(binding_name);
      return result;
    elseif (token_content:starts_with("the "))
      after_article = token_content[5..$]:trim();
      binding_name = tosym(after_article);
      result = $sub:the(binding_name);
      return result;
    endif

    "Check for capitalized variants of above";
    if (token_content:starts_with("A "))
      after_article = token_content[3..$]:trim();
      binding_name = tosym(after_article);
      result = $sub:ac(binding_name);
      return result;
    elseif (token_content:starts_with("An "))
      after_article = token_content[4..$]:trim();
      binding_name = tosym(after_article);
      result = $sub:ac(binding_name);
      return result;
    elseif (token_content:starts_with("The "))
      after_article = token_content[5..$]:trim();
      binding_name = tosym(after_article);
      result = $sub:thec(binding_name);
      return result;
    endif

    "Check for known verbs and pronouns";
    "Name substitutions: n, nc, d, dc, i, ic, l, lc, t, tc";
    if (token_content == "n")
      return $sub:n();
    elseif (token_content == "nc")
      return $sub:nc();
    elseif (token_content == "d")
      return $sub:d();
    elseif (token_content == "dc")
      return $sub:dc();
    elseif (token_content == "i")
      return $sub:i();
    elseif (token_content == "ic")
      return $sub:ic();
    elseif (token_content == "l")
      return $sub:l();
    elseif (token_content == "lc")
      return $sub:lc();
    elseif (token_content == "t")
      return $sub:t();
    elseif (token_content == "tc")
      return $sub:tc();
    endif

    "Actor pronouns: s, o, p, q, r (with optional c suffix)";
    if (token_content == "s")
      return $sub:s();
    elseif (token_content == "sc")
      return $sub:sc();
    elseif (token_content == "o")
      return $sub:o();
    elseif (token_content == "oc")
      return $sub:oc();
    elseif (token_content == "p")
      return $sub:p();
    elseif (token_content == "pc")
      return $sub:pc();
    elseif (token_content == "q")
      return $sub:q();
    elseif (token_content == "qc")
      return $sub:qc();
    elseif (token_content == "r")
      return $sub:r();
    elseif (token_content == "rc")
      return $sub:rc();
    endif

    "Object pronouns with _dobj and _iobj suffixes";
    if (token_content == "s_dobj")
      return $sub:s_dobj();
    elseif (token_content == "sc_dobj")
      return $sub:sc_dobj();
    elseif (token_content == "o_dobj")
      return $sub:o_dobj();
    elseif (token_content == "oc_dobj")
      return $sub:oc_dobj();
    elseif (token_content == "p_dobj")
      return $sub:p_dobj();
    elseif (token_content == "pc_dobj")
      return $sub:pc_dobj();
    elseif (token_content == "q_dobj")
      return $sub:q_dobj();
    elseif (token_content == "qc_dobj")
      return $sub:qc_dobj();
    elseif (token_content == "r_dobj")
      return $sub:r_dobj();
    elseif (token_content == "rc_dobj")
      return $sub:rc_dobj();
    endif

    if (token_content == "s_iobj")
      return $sub:s_iobj();
    elseif (token_content == "sc_iobj")
      return $sub:sc_iobj();
    elseif (token_content == "o_iobj")
      return $sub:o_iobj();
    elseif (token_content == "oc_iobj")
      return $sub:oc_iobj();
    elseif (token_content == "p_iobj")
      return $sub:p_iobj();
    elseif (token_content == "pc_iobj")
      return $sub:pc_iobj();
    elseif (token_content == "q_iobj")
      return $sub:q_iobj();
    elseif (token_content == "qc_iobj")
      return $sub:qc_iobj();
    elseif (token_content == "r_iobj")
      return $sub:r_iobj();
    elseif (token_content == "rc_iobj")
      return $sub:rc_iobj();
    endif

    "Verb conjugations";
    if (token_content == "be")
      return $sub:verb_be();
    elseif (token_content == "be_dobj")
      return $sub:verb_be_dobj();
    elseif (token_content == "be_iobj")
      return $sub:verb_be_iobj();
    elseif (token_content == "have")
      return $sub:verb_have();
    elseif (token_content == "have_dobj")
      return $sub:verb_have_dobj();
    elseif (token_content == "have_iobj")
      return $sub:verb_have_iobj();
    elseif (token_content == "look")
      return $sub:verb_look();
    elseif (token_content == "look_dobj")
      return $sub:verb_look_dobj();
    elseif (token_content == "look_iobj")
      return $sub:verb_look_iobj();
    endif

    "If nothing matched, treat as binding";
    binding_name = tosym(token_content);
    result = $sub:binding(binding_name);
    return result;
  endverb

  verb decompile (this none this) owner: HACKER flags: "rxd"
    "Reconstruct template string from compiled content list.";
    {content} = args;
    typeof(content) != LIST && raise(E_TYPE, "content must be list");

    result = "";
    for item in (content)
      if (typeof(item) == STR)
        result = result + item;
      elseif (typeof(item) == FLYWEIGHT)
        result = result + this:_reconstruct_token(item);
      else
        result = result + tostr(item);
      endif
    endfor

    return result;
  endverb

  verb _reconstruct_token (this none this) owner: HACKER flags: "rxd"
    "Reconstruct {token} syntax from a flyweight.";
    {fw} = args;
    typeof(fw) != FLYWEIGHT && raise(E_TYPE, "must be flyweight");

    token_type = fw.type;
    if (!token_type)
      return "{?}";
    endif

    "Self-alternation";
    if (token_type == 'self_alt)
      for_self = fw.for_self;
      for_others = fw.for_others;
      return "{" + tostr(for_self) + "|" + tostr(for_others) + "}";
    endif

    "Articles";
    if (token_type == 'article_a)
      binding_name = fw.binding_name;
      capitalize = fw.capitalize;
      if (capitalize)
        article_prefix = "A";
      else
        article_prefix = "a";
      endif
      return "{" + article_prefix + " " + tostr(binding_name) + "}";
    elseif (token_type == 'article_the)
      binding_name = fw.binding_name;
      capitalize = fw.capitalize;
      if (capitalize)
        article_prefix = "The";
      else
        article_prefix = "the";
      endif
      return "{" + article_prefix + " " + tostr(binding_name) + "}";
    endif

    "Bindings";
    if (token_type == 'binding)
      binding_name = fw.binding_name;
      capitalize = fw.capitalize;
      name_str = tostr(binding_name);
      if (capitalize)
        name_str = name_str:capitalize();
      endif
      return "{" + name_str + "}";
    endif

    "Simple token types (pronouns, name subs, verbs)";
    "Map type symbols back to token names";
    type_map = [
      'actor -> 'n,
      'dobj -> 'd,
      'iobj -> 'i,
      'location -> 'l,
      'this -> 't,
      'subject -> 's,
      'object -> 'o,
      'pos_adj -> 'p,
      'pos_noun -> 'q,
      'reflexive -> 'r,
      'verb_be -> 'be,
      'verb_have -> 'have,
      'verb_look -> 'look
    ];

    capitalize = fw.capitalize;
    if (maphaskey(type_map, token_type))
      base = type_map[token_type];
      if (capitalize)
        token_name = tostr(base) + "c";
      else
        token_name = tostr(base);
      endif
      return "{" + token_name + "}";
    endif

    "Object-specific versions (actor_*, dobj_*, iobj_*)";
    token_str = tostr(token_type);
    if (token_str:starts_with("actor_"))
      if (capitalize)
        suffix = "c";
      else
        suffix = "";
      endif
      base = token_str[7..$];
      "Map base pronoun types";
      if (base == "subject")
        return "{s" + suffix + "}";
      elseif (base == "object")
        return "{o" + suffix + "}";
      elseif (base == "pos_adj")
        return "{p" + suffix + "}";
      elseif (base == "pos_noun")
        return "{q" + suffix + "}";
      elseif (base == "reflexive")
        return "{r" + suffix + "}";
      endif
    endif
    if (token_str:starts_with("dobj_"))
      if (capitalize)
        suffix = "c_dobj";
      else
        suffix = "_dobj";
      endif
      base = token_str[6..$];
      "Remove _subject suffix if present, etc.";
      if (base == "subject")
        return "{s" + suffix + "}";
      elseif (base == "object")
        return "{o" + suffix + "}";
      elseif (base == "pos_adj")
        return "{p" + suffix + "}";
      elseif (base == "pos_noun")
        return "{q" + suffix + "}";
      elseif (base == "reflexive")
        return "{r" + suffix + "}";
      elseif (base == "verb_be")
        return "{be_dobj}";
      elseif (base == "verb_have")
        return "{have_dobj}";
      elseif (base == "verb_look")
        return "{look_dobj}";
      endif
    endif

    if (token_str:starts_with("iobj_"))
      if (capitalize)
        suffix = "c_iobj";
      else
        suffix = "_iobj";
      endif
      base = token_str[6..$];
      if (base == "subject")
        return "{s" + suffix + "}";
      elseif (base == "object")
        return "{o" + suffix + "}";
      elseif (base == "pos_adj")
        return "{p" + suffix + "}";
      elseif (base == "pos_noun")
        return "{q" + suffix + "}";
      elseif (base == "reflexive")
        return "{r" + suffix + "}";
      elseif (base == "verb_be")
        return "{be_iobj}";
      elseif (base == "verb_have")
        return "{have_iobj}";
      elseif (base == "verb_look")
        return "{look_iobj}";
      endif
    endif

    "Fallback";
    return "{?" + token_str + "?}";
  endverb

  verb test_compile_simple_binding (this none this) owner: HACKER flags: "rxd"
    "Test compile with simple binding.";
    result = this:compile("You see {actor}.");
    length(result) != 3 && raise(E_ASSERT);
    result[1] != "You see " && raise(E_ASSERT);
    typeof(result[2]) != FLYWEIGHT && raise(E_ASSERT);
    result[2].type != 'binding && raise(E_ASSERT);
    result[3] != "." && raise(E_ASSERT);
    return true;
  endverb

  verb test_compile_article (this none this) owner: HACKER flags: "rxd"
    "Test compile with article.";
    result = this:compile("{the direction}");
    length(result) != 1 && raise(E_ASSERT);
    typeof(result[1]) != FLYWEIGHT && raise(E_ASSERT);
    result[1].type != 'article_the && raise(E_ASSERT);
    result[1].binding_name != 'direction && raise(E_ASSERT);
    return true;
  endverb

  verb test_compile_self_alt (this none this) owner: HACKER flags: "rxd"
    "Test compile with self-alternation.";
    result = this:compile("{tired|exhausted}");
    length(result) != 1 && raise(E_ASSERT);
    typeof(result[1]) != FLYWEIGHT && raise(E_ASSERT);
    result[1].type != 'self_alt && raise(E_ASSERT);
    result[1].for_self != "tired" && raise(E_ASSERT);
    result[1].for_others != "exhausted" && raise(E_ASSERT);
    return true;
  endverb

  verb test_compile_mixed (this none this) owner: HACKER flags: "rxd"
    "Test compile with mixed content.";
    result = this:compile("{nc} heads {the direction}.");
    length(result) != 4 && raise(E_ASSERT);
    typeof(result[1]) != FLYWEIGHT && raise(E_ASSERT);
    result[2] != " heads " && raise(E_ASSERT);
    typeof(result[3]) != FLYWEIGHT && raise(E_ASSERT);
    result[4] != "." && raise(E_ASSERT);
    return true;
  endverb

  verb test_decompile_simple (this none this) owner: HACKER flags: "rxd"
    "Test decompile reconstructs template.";
    original = "You see {actor}.";
    compiled = this:compile(original);
    decompiled = this:decompile(compiled);
    decompiled != original && raise(E_ASSERT);
    return true;
  endverb

  verb test_decompile_nc_d (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test decompile with nc and d substitutions.";
    original = "{nc} dropped {d}.";
    compiled = this:compile(original);


    decompiled = this:decompile(compiled);
    decompiled != original && raise(E_ASSERT, "Decompilation failed: " + decompiled);
    return true;
  endverb

endobject
