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
    len = length(template);
    while (pos <= len)
      token_start_offset = index(template[pos..$], "{");
      if (!token_start_offset)
        pos <= len && (content = {@content, template[pos..$]});
        break;
      endif
      token_start = pos + token_start_offset - 1;
      token_start > pos && (content = {@content, template[pos..token_start - 1]});
      token_end_offset = index(template[token_start + 1..$], "}");
      !token_end_offset && raise(E_INVARG, "Unclosed brace in template at position " + token_start);
      token_end = token_start + token_end_offset;
      fw = this:_parse_token(template[token_start + 1..token_end - 1]);
      typeof(fw) == FLYWEIGHT && (content = {@content, fw});
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
    "Articles";
    article_patterns = {{"a ", 3, "a"}, {"an ", 4, "a"}, {"the ", 5, "the"}, {"A ", 3, "ac"}, {"An ", 4, "ac"}, {"The ", 5, "thec"}};
    for pattern in (article_patterns)
      {prefix, skip, method} = pattern;
      if (token_content:starts_with(prefix))
        binding_name = tosym(token_content[skip..$]:trim());
        return $sub:(method)(binding_name);
      endif
    endfor
    "Direct dispatch for known tokens";
    token_map = ["n" -> {"n", {}}, "nc" -> {"nc", {}}, "d" -> {"d", {}}, "dc" -> {"dc", {}}, "i" -> {"i", {}}, "ic" -> {"ic", {}}, "l" -> {"l", {}}, "lc" -> {"lc", {}}, "t" -> {"t", {}}, "tc" -> {"tc", {}}, "s" -> {"s", {}}, "sc" -> {"sc", {}}, "o" -> {"o", {}}, "oc" -> {"oc", {}}, "p" -> {"p", {}}, "pc" -> {"pc", {}}, "q" -> {"q", {}}, "qc" -> {"qc", {}}, "r" -> {"r", {}}, "rc" -> {"rc", {}}, "s_dobj" -> {"s_dobj", {}}, "sc_dobj" -> {"sc_dobj", {}}, "o_dobj" -> {"o_dobj", {}}, "oc_dobj" -> {"oc_dobj", {}}, "p_dobj" -> {"p_dobj", {}}, "pc_dobj" -> {"pc_dobj", {}}, "q_dobj" -> {"q_dobj", {}}, "qc_dobj" -> {"qc_dobj", {}}, "r_dobj" -> {"r_dobj", {}}, "rc_dobj" -> {"rc_dobj", {}}, "s_iobj" -> {"s_iobj", {}}, "sc_iobj" -> {"sc_iobj", {}}, "o_iobj" -> {"o_iobj", {}}, "oc_iobj" -> {"oc_iobj", {}}, "p_iobj" -> {"p_iobj", {}}, "pc_iobj" -> {"pc_iobj", {}}, "q_iobj" -> {"q_iobj", {}}, "qc_iobj" -> {"qc_iobj", {}}, "r_iobj" -> {"r_iobj", {}}, "rc_iobj" -> {"rc_iobj", {}}, "be" -> {"verb_be", {}}, "be_dobj" -> {"verb_be_dobj", {}}, "be_iobj" -> {"verb_be_iobj", {}}, "have" -> {"verb_have", {}}, "have_dobj" -> {"verb_have_dobj", {}}, "have_iobj" -> {"verb_have_iobj", {}}, "look" -> {"verb_look", {}}, "look_dobj" -> {"verb_look_dobj", {}}, "look_iobj" -> {"verb_look_iobj", {}}];
    if (maphaskey(token_map, token_content))
      {method, method_args} = token_map[token_content];
      return $sub:(method)(@method_args);
    endif
    "Fallback: treat as binding";
    return $sub:binding(tosym(token_content));
  endverb

  verb decompile (this none this) owner: HACKER flags: "rxd"
    "Reconstruct template string from compiled content list.";
    {content} = args;
    typeof(content) != LIST && raise(E_TYPE, "content must be list");
    result = "";
    for item in (content)
      result = result + (typeof(item) == STR ? item | typeof(item) == FLYWEIGHT ? this:_reconstruct_token(item) | tostr(item));
    endfor
    return result;
  endverb

  verb _reconstruct_token (this none this) owner: HACKER flags: "rxd"
    "Reconstruct {token} syntax from a flyweight.";
    {fw} = args;
    typeof(fw) != FLYWEIGHT && raise(E_TYPE, "must be flyweight");
    token_type = fw.type;
    !token_type && return "{?}";
    token_type == 'self_alt && return "{" + tostr(fw.for_self) + "|" + tostr(fw.for_others) + "}";
    if (token_type == 'article_a)
      prefix = fw.capitalize ? "A" | "a";
      return "{" + prefix + " " + tostr(fw.binding_name) + "}";
    endif
    if (token_type == 'article_the)
      prefix = fw.capitalize ? "The" | "the";
      return "{" + prefix + " " + tostr(fw.binding_name) + "}";
    endif
    if (token_type == 'binding)
      name_str = tostr(fw.binding_name);
      return "{" + (fw.capitalize ? name_str:capitalize() | name_str) + "}";
    endif
    "Map type symbols back to token names";
    type_map = ['actor -> "n", 'dobj -> "d", 'iobj -> "i", 'location -> "l", 'this -> "t", 'subject -> "s", 'object -> "o", 'pos_adj -> "p", 'pos_noun -> "q", 'reflexive -> "r", 'verb_be -> "be", 'verb_have -> "have", 'verb_look -> "look"];
    if (maphaskey(type_map, token_type))
      base = type_map[token_type];
      return "{" + base + (fw.capitalize ? "c" | "") + "}";
    endif
    "Object-specific versions (dobj_*, iobj_*)";
    token_str = tostr(token_type);
    pronoun_map = ["subject" -> "s", "object" -> "o", "pos_adj" -> "p", "pos_noun" -> "q", "reflexive" -> "r"];
    verb_map = ["verb_be" -> "be", "verb_have" -> "have", "verb_look" -> "look"];
    if (token_str:starts_with("dobj_"))
      base = token_str[6..$];
      maphaskey(verb_map, base) && return "{" + verb_map[base] + "_dobj}";
      suffix = fw.capitalize ? "c_dobj" | "_dobj";
      maphaskey(pronoun_map, base) && return "{" + pronoun_map[base] + suffix + "}";
    endif
    if (token_str:starts_with("iobj_"))
      base = token_str[6..$];
      maphaskey(verb_map, base) && return "{" + verb_map[base] + "_iobj}";
      suffix = fw.capitalize ? "c_iobj" | "_iobj";
      maphaskey(pronoun_map, base) && return "{" + pronoun_map[base] + suffix + "}";
    endif
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
