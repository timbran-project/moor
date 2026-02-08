object SUB_UTILS
  name: "Substitution Utilities"
  parent: ROOT
  owner: HACKER
  readable: true

  property article_patterns (owner: ARCH_WIZARD, flags: "rc") = {
    {"a ", 3, "a"},
    {"an ", 4, "a"},
    {"the ", 5, "the"},
    {"A ", 3, "ac"},
    {"An ", 4, "ac"},
    {"The ", 5, "thec"}
  };
  property pronoun_map (owner: ARCH_WIZARD, flags: "rc") = [
    "object" -> "o",
    "pos_adj" -> "p",
    "pos_noun" -> "q",
    "reflexive" -> "r",
    "subject" -> "s"
  ];
  property token_map (owner: ARCH_WIZARD, flags: "rc") = [
    "be" -> {"verb_be", {}},
    "be_dobj" -> {"verb_be_dobj", {}},
    "be_iobj" -> {"verb_be_iobj", {}},
    "d" -> {"d", {}},
    "dc" -> {"dc", {}},
    "have" -> {"verb_have", {}},
    "have_dobj" -> {"verb_have_dobj", {}},
    "have_iobj" -> {"verb_have_iobj", {}},
    "i" -> {"i", {}},
    "ic" -> {"ic", {}},
    "l" -> {"l", {}},
    "lc" -> {"lc", {}},
    "look" -> {"verb_look", {}},
    "look_dobj" -> {"verb_look_dobj", {}},
    "look_iobj" -> {"verb_look_iobj", {}},
    "n" -> {"n", {}},
    "nc" -> {"nc", {}},
    "o" -> {"o", {}},
    "o_dobj" -> {"o_dobj", {}},
    "o_iobj" -> {"o_iobj", {}},
    "oc" -> {"oc", {}},
    "oc_dobj" -> {"oc_dobj", {}},
    "oc_iobj" -> {"oc_iobj", {}},
    "p" -> {"p", {}},
    "p_dobj" -> {"p_dobj", {}},
    "p_iobj" -> {"p_iobj", {}},
    "pc" -> {"pc", {}},
    "pc_dobj" -> {"pc_dobj", {}},
    "pc_iobj" -> {"pc_iobj", {}},
    "q" -> {"q", {}},
    "q_dobj" -> {"q_dobj", {}},
    "q_iobj" -> {"q_iobj", {}},
    "qc" -> {"qc", {}},
    "qc_dobj" -> {"qc_dobj", {}},
    "qc_iobj" -> {"qc_iobj", {}},
    "r" -> {"r", {}},
    "r_dobj" -> {"r_dobj", {}},
    "r_iobj" -> {"r_iobj", {}},
    "rc" -> {"rc", {}},
    "rc_dobj" -> {"rc_dobj", {}},
    "rc_iobj" -> {"rc_iobj", {}},
    "s" -> {"s", {}},
    "s_dobj" -> {"s_dobj", {}},
    "s_iobj" -> {"s_iobj", {}},
    "sc" -> {"sc", {}},
    "sc_dobj" -> {"sc_dobj", {}},
    "sc_iobj" -> {"sc_iobj", {}},
    "t" -> {"t", {}},
    "tc" -> {"tc", {}}
  ];
  property typemap (owner: ARCH_WIZARD, flags: "rc") = [
    'verb_be -> "be",
    'verb_have -> "have",
    'verb_look -> "look",
    'this -> "t",
    'location -> "l",
    'dobj -> "d",
    'iobj -> "i",
    'subject -> "s",
    'actor -> "n",
    'pos_adj -> "p",
    'object -> "o",
    'reflexive -> "r",
    'pos_noun -> "q"
  ];
  property verb_map (owner: ARCH_WIZARD, flags: "rc") = ["verb_be" -> "be", "verb_have" -> "have", "verb_look" -> "look"];

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
    "### compile(template_string) \u2192 list",
    "",
    "Parses a template string and returns a list of strings and $sub flyweights.",
    "",
    "### decompile(content_list) \u2192 string",
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
    typeof(template) != TYPE_STR && raise(E_TYPE, "template must be string");
    content = {};
    pos = 1;
    len = length(template);
    while (pos <= len)
      token_start = index(template, "{", 0, pos - 1);
      if (!token_start)
        content = {@content, template[pos..$]};
        break;
      endif
      if (token_start > pos)
        content = {@content, template[pos..token_start - 1]};
      endif
      depth = 1;
      scan_pos = token_start + 1;
      token_end = 0;
      while (scan_pos <= len)
        next_open = index(template, "{", 0, scan_pos - 1);
        next_close = index(template, "}", 0, scan_pos - 1);
        if (!next_close)
          raise(E_INVARG, "Unclosed brace in template at position " + tostr(token_start));
        endif
        if (next_open && next_open < next_close)
          depth = depth + 1;
          scan_pos = next_open + 1;
        else
          depth = depth - 1;
          if (depth == 0)
            token_end = next_close;
            break;
          endif
          scan_pos = next_close + 1;
        endif
      endwhile
      fw = this:_parse_token(template[token_start + 1..token_end - 1]);
      typeof(fw) == TYPE_FLYWEIGHT && (content = {@content, fw});
      pos = token_end + 1;
    endwhile
    return content;
  endverb

  verb _parse_token (this none this) owner: HACKER flags: "rxd"
    "Parse a single {token} and return corresponding $sub flyweight.";
    {token_content} = args;
    token_content = token_content:trim();
    "Self-alternation (contains |)";
    pipe_index = index(token_content, "|");
    if (pipe_index)
      parts = token_content:split("|");
      length(parts) != 2 && raise(E_INVARG, "Self-alternation must have exactly 2 parts: " + token_content);
      return $sub:self_alt(parts[1]:trim(), parts[2]:trim());
    endif
    "Articles from property";
    for pattern in (this.article_patterns)
      {prefix, skip, method} = pattern;
      if (token_content:starts_with(prefix))
        binding_name = tosym(token_content[skip..$]:trim());
        return $sub:(method)(binding_name);
      endif
    endfor
    "Direct dispatch from property";
    if (maphaskey(this.token_map, token_content))
      {method, method_args} = this.token_map[token_content];
      return $sub:(method)(@method_args);
    endif
    "Fallback: treat as binding";
    return $sub:binding(tosym(token_content));
  endverb

  verb decompile (this none this) owner: HACKER flags: "rxd"
    "Reconstruct template string from compiled content list.";
    {content} = args;
    typeof(content) != TYPE_LIST && raise(E_TYPE, "content must be list");
    result = "";
    for item in (content)
      result = result + (typeof(item) == TYPE_STR ? item | (typeof(item) == TYPE_FLYWEIGHT ? this:_reconstruct_token(item) | tostr(item)));
    endfor
    return result;
  endverb

  verb _reconstruct_token (this none this) owner: HACKER flags: "rxd"
    "Reconstruct {token} syntax from a flyweight.";
    {fw} = args;
    typeof(fw) != TYPE_FLYWEIGHT && raise(E_TYPE, "must be flyweight");
    token_type = fw.type;
    !token_type && return "{?}";
    capitalize = `fw.capitalize ! E_PROPNF => false';
    token_type == 'self_alt && return "{" + tostr(fw.for_self) + "|" + tostr(fw.for_others) + "}";
    if (token_type == 'article_a)
      prefix = capitalize ? "A" | "a";
      return "{" + prefix + " " + tostr(fw.binding_name) + "}";
    endif
    if (token_type == 'article_the)
      prefix = capitalize ? "The" | "the";
      return "{" + prefix + " " + tostr(fw.binding_name) + "}";
    endif
    if (token_type == 'binding)
      name_str = tostr(fw.binding_name);
      return "{" + (capitalize ? name_str:capitalize() | name_str) + "}";
    endif
    "Map type symbols back to token names";
    if (maphaskey(this.typemap, token_type))
      base = this.typemap[token_type];
      return "{" + base + (capitalize ? "c" | "") + "}";
    endif
    "Object-specific versions (dobj_*, iobj_*)";
    token_str = tostr(token_type);
    if (token_str:starts_with("dobj_"))
      base = token_str[6..$];
      maphaskey(this.verb_map, base) && return "{" + this.verb_map[base] + "_dobj}";
      suffix = capitalize ? "c_dobj" | "_dobj";
      maphaskey(this.pronoun_map, base) && return "{" + this.pronoun_map[base] + suffix + "}";
    endif
    if (token_str:starts_with("iobj_"))
      base = token_str[6..$];
      maphaskey(this.verb_map, base) && return "{" + this.verb_map[base] + "_iobj}";
      suffix = capitalize ? "c_iobj" | "_iobj";
      maphaskey(this.pronoun_map, base) && return "{" + this.pronoun_map[base] + suffix + "}";
    endif
    return "{?" + token_str + "?}";
  endverb

  verb test_compile_simple_binding (this none this) owner: HACKER flags: "rxd"
    "Test compile with simple binding.";
    result = this:compile("You see {actor}.");
    length(result) != 3 && raise(E_ASSERT);
    result[1] != "You see " && raise(E_ASSERT);
    typeof(result[2]) != TYPE_FLYWEIGHT && raise(E_ASSERT);
    result[2].type != 'binding && raise(E_ASSERT);
    result[3] != "." && raise(E_ASSERT);
    return true;
  endverb

  verb test_compile_article (this none this) owner: HACKER flags: "rxd"
    "Test compile with article.";
    result = this:compile("{the direction}");
    length(result) != 1 && raise(E_ASSERT);
    typeof(result[1]) != TYPE_FLYWEIGHT && raise(E_ASSERT);
    result[1].type != 'article_the && raise(E_ASSERT);
    result[1].binding_name != 'direction && raise(E_ASSERT);
    return true;
  endverb

  verb test_compile_self_alt (this none this) owner: HACKER flags: "rxd"
    "Test compile with self-alternation.";
    result = this:compile("{tired|exhausted}");
    length(result) != 1 && raise(E_ASSERT);
    typeof(result[1]) != TYPE_FLYWEIGHT && raise(E_ASSERT);
    result[1].type != 'self_alt && raise(E_ASSERT);
    result[1].for_self != "tired" && raise(E_ASSERT);
    result[1].for_others != "exhausted" && raise(E_ASSERT);
    return true;
  endverb

  verb test_compile_mixed (this none this) owner: HACKER flags: "rxd"
    "Test compile with mixed content.";
    result = this:compile("{nc} heads {the direction}.");
    length(result) != 4 && raise(E_ASSERT);
    typeof(result[1]) != TYPE_FLYWEIGHT && raise(E_ASSERT);
    result[2] != " heads " && raise(E_ASSERT);
    typeof(result[3]) != TYPE_FLYWEIGHT && raise(E_ASSERT);
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

  verb test_compile_nested (this none none) owner: ARCH_WIZARD flags: "rxd"
    "Test compilation of nested braces.";
    template = "Look at {the {adj} key}.";
    result = this:compile(template);
    "Expected: 'Look at ', FW(article_the, binding='{adj} key'), '.'";
    "Note: The current parser treats the inner content as a raw string binding name because _parse_token doesnt recursively compile.";
    "However, the key improvement is that it DOESNT choke on the inner braces.";
    length(result) != 3 && raise(E_ASSERT, "Result length mismatch: " + tostr(length(result)));
    result[1] != "Look at " && raise(E_ASSERT, "Prefix mismatch");
    typeof(result[2]) != TYPE_FLYWEIGHT && raise(E_ASSERT, "Middle token not flyweight");
    "The binding name should capture the full inner content including braces";
    "If the parser stopped at the first }, it would be '{adj'";
    binding = tostr(result[2].binding_name);
    binding != "{adj} key" && raise(E_ASSERT, "Binding content mismatch. Got: " + binding);
    return true;
  endverb

  verb test_compile_properties (this none none) owner: ARCH_WIZARD flags: "rxd"
    "Test property-based map lookups.";
    "Test direct token map";
    res1 = this:compile("You are {n}.");
    res1[2].type != 'actor && raise(E_ASSERT, "Failed to map {n} to actor");
    "Test verb map lookup via _parse_token logic";
    res2 = this:compile("Use {be}.");
    res2[2].type != 'verb_be && raise(E_ASSERT, "Failed to map {be} to verb_be");
    "Test specific object suffix logic (dobj_*)";
    res3 = this:compile("It is {be_dobj}.");
    "Note: $sub:verb_be returns 'dobj_verb_be' when called as verb_be_dobj";
    res3[2].type != 'dobj_verb_be && raise(E_ASSERT, "Failed to map {be_dobj}. Got: " + tostr(res3[2].type));
    return true;
  endverb
endobject
