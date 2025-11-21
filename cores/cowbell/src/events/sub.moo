object SUB
  name: "Substitutions Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Flyweight delegate and factory for template substitution in events.";
  override import_export_hierarchy = {"events"};
  override import_export_id = "sub";
  override object_documentation = {
    "# $sub - Event Substitution System",
    "",
    "## Overview",
    "",
    "The `$sub` system provides template-based text substitution for events in the MOO. It allows you to write narrative",
    "descriptions that automatically adapt based on perspective (first-person vs third-person) and grammatical context.",
    "",
    "Substitutions are created as lightweight flyweight objects that get evaluated when events are rendered to players. This",
    "means the same event can produce different text for different viewers.",
    "",
    "## Basic Concept",
    "",
    "When you create an event, you build content using substitution flyweights:",
    "",
    "```moo",
    "content = {$sub:nc(), \" picks up \", $sub:d(), \".\"};",
    "```",
    "",
    "When this event is rendered:",
    "",
    "- **To the actor**: \"You pick up the sword.\"",
    "- **To others**: \"Alice picks up the sword.\"",
    "",
    "## Name Substitutions",
    "",
    "These substitute names of objects and participants in the event.",
    "",
    "### Actor Names",
    "",
    "| Verb        | Output                 | Example (actor is Alice) |",
    "|-------------|------------------------|--------------------------|",
    "| `$sub:n()`  | Actor name             | \"Alice\" / \"you\"          |",
    "| `$sub:nc()` | Capitalized actor name | \"Alice\" / \"You\"          |",
    "",
    "### Object Names",
    "",
    "| Verb        | Description          | Example               |",
    "|-------------|----------------------|-----------------------|",
    "| `$sub:d()`  | Direct object        | \"the sword\" / \"you\"   |",
    "| `$sub:dc()` | Capitalized dobj     | \"The sword\" / \"You\"   |",
    "| `$sub:i()`  | Indirect object      | \"the chest\" / \"you\"   |",
    "| `$sub:ic()` | Capitalized iobj     | \"The chest\" / \"You\"   |",
    "| `$sub:t()`  | This object          | \"the door\" / \"you\"    |",
    "| `$sub:tc()` | Capitalized this     | \"The door\" / \"You\"    |",
    "| `$sub:l()`  | Location             | \"the tavern\" / \"here\" |",
    "| `$sub:lc()` | Capitalized location | \"The tavern\" / \"Here\" |",
    "",
    "## Pronoun Substitutions",
    "",
    "These substitute pronouns based on the actor's or object's gender settings.",
    "",
    "### Actor Pronouns",
    "",
    "| Verb       | Type                 | Example (he/him)       | Example (they/them)       |",
    "|------------|----------------------|------------------------|---------------------------|",
    "| `$sub:s()` | Subject              | \"he\" / \"you\"           | \"they\" / \"you\"            |",
    "| `$sub:o()` | Object               | \"him\" / \"you\"          | \"them\" / \"you\"            |",
    "| `$sub:p()` | Possessive adjective | \"his\" / \"your\"         | \"their\" / \"your\"          |",
    "| `$sub:q()` | Possessive noun      | \"his\" / \"yours\"        | \"theirs\" / \"yours\"        |",
    "| `$sub:r()` | Reflexive            | \"himself\" / \"yourself\" | \"themselves\" / \"yourself\" |",
    "",
    "Add `c` for capitalized versions: `$sub:sc()`, `$sub:oc()`, etc.",
    "",
    "### Direct Object Pronouns",
    "",
    "| Verb            | Type            | Example              |",
    "|-----------------|-----------------|----------------------|",
    "| `$sub:s_dobj()` | Subject         | \"he\" / \"it\"          |",
    "| `$sub:o_dobj()` | Object          | \"him\" / \"it\"         |",
    "| `$sub:p_dobj()` | Possessive adj  | \"his\" / \"its\"        |",
    "| `$sub:q_dobj()` | Possessive noun | \"his\" / \"its\"        |",
    "| `$sub:r_dobj()` | Reflexive       | \"himself\" / \"itself\" |",
    "",
    "Also available with capitalization: `$sub:sc_dobj()`, etc.",
    "",
    "### Indirect Object Pronouns",
    "",
    "Same pattern as dobj, but using `_iobj` suffix:",
    "",
    "- `$sub:s_iobj()`, `$sub:o_iobj()`, `$sub:p_iobj()`, etc.",
    "- Capitalized: `$sub:sc_iobj()`, `$sub:oc_iobj()`, etc.",
    "",
    "## Verb Conjugation",
    "",
    "These conjugate verbs based on person and number.",
    "",
    "### Actor Verb Conjugation",
    "",
    "| Verb               | 2nd person (you) | 3rd person (he/she/it) |",
    "|--------------------|------------------|------------------------|",
    "| `$sub:verb_be()`   | \"are\"            | \"is\"                   |",
    "| `$sub:verb_have()` | \"have\"           | \"has\"                  |",
    "| `$sub:verb_look()` | \"look\"           | \"looks\"                |",
    "",
    "### Object Verb Conjugation",
    "",
    "Same verbs available with `_dobj` or `_iobj` suffix:",
    "",
    "- `$sub:verb_be_dobj()`, `$sub:verb_have_iobj()`, etc.",
    "",
    "## Self-Alternation",
    "",
    "The `self_alt()` method chooses between two alternatives based on whether the viewer is the actor.",
    "",
    "```moo",
    "$sub:self_alt(for_self, for_others)",
    "```",
    "",
    "### Basic Usage",
    "",
    "```moo",
    "content = {$sub:nc(), \" \", $sub:self_alt(\"feel\", \"feels\"), \" tired.\"};",
    "```",
    "",
    "- **To actor**: \"You feel tired.\"",
    "- **To others**: \"Alice feels tired.\"",
    "",
    "### Nested Substitutions",
    "",
    "You can nest substitutions inside `self_alt()`:",
    "",
    "```moo",
    "content = {",
    "    $sub:nc(), \" \", $sub:self_alt(\"try\", \"tries\"),",
    "    \" to pet the cat, but it swats \",",
    "    $sub:self_alt(\"your\", $sub:p()), \" hand away.\"",
    "};",
    "```",
    "",
    "- **To actor**: \"You try to pet the cat, but it swats **your** hand away.\"",
    "- **To others**: \"Alice tries to pet the cat, but it swats **her** hand away.\"",
    "",
    "The nested `$sub:p()` is only evaluated when the viewer is not the actor.",
    "",
    "### Capitalization",
    "",
    "Use `$sub:self_altc()` to capitalize the result:",
    "",
    "```moo",
    "$sub:self_altc(\"you're\", \"they're\")",
    "```",
    "",
    "## Complete Example",
    "",
    "Here's a full example of building event content:",
    "",
    "```moo",
    "verb pet (this none this)",
    "    dobj = args[1];",
    "",
    "    if (!dobj:allows_petting())",
    "        \"Build content for failed petting attempt\";",
    "        content = {",
    "            $sub:nc(), \" \", $sub:self_alt(\"try\", \"tries\"),",
    "            \" to pet \", $sub:d(), \", but \", $sub:d(),",
    "            \" hisses and swats \", $sub:self_alt(\"your\", $sub:p()),",
    "            \" hand away.\"",
    "        };",
    "",
    "        event = $event:mk(player, #-1, this, dobj, #-1, content, {});",
    "        event:send_to_location();",
    "",
    "        \"Tell actor they failed\";",
    "        notify(player, \"The cat doesn't want to be petted right now.\");",
    "        return;",
    "    endif",
    "",
    "    \"Build content for successful petting\";",
    "    content = {",
    "        $sub:nc(), \" \", $sub:self_alt(\"pet\", \"pets\"), \" \", $sub:d(),",
    "        \" gently, and \", $sub:d(), \" purrs contentedly.\"",
    "    };",
    "",
    "    event = $event:mk(player, #-1, this, dobj, #-1, content, {});",
    "    event:send_to_location();",
    "endverb",
    "```",
    "",
    "When Alice pets the friendly cat:",
    "",
    "- **Alice sees**: \"You pet the friendly cat gently, and the friendly cat purrs contentedly.\"",
    "- **Bob sees**: \"Alice pets the friendly cat gently, and the friendly cat purrs contentedly.\"",
    "",
    "When Alice tries to pet the grumpy cat:",
    "",
    "- **Alice sees**: \"You try to pet the grumpy cat, but the grumpy cat hisses and swats your hand away.\"",
    "- **Bob sees**: \"Alice tries to pet the grumpy cat, but the grumpy cat hisses and swats her hand away.\"",
    "",
    "## Implementation Notes",
    "",
    "- All substitution verbs return flyweight objects with a `.type` property",
    "- The actual substitution happens when the event is rendered via `:render_as()` or `:compose()`",
    "- Substitutions check if `event.actor == render_for` to determine perspective",
    "- The `name_sub()` method handles the \"you\" vs object name logic",
    "- Nested substitutions are evaluated recursively during rendering",
    "- If a dobj/iobj is missing, placeholder text like `\"<no-dobj>\"` is returned",
    "",
    "## Phrase Utilities",
    "",
    "The `$sub:phrase()` verb provides text manipulation:",
    "",
    "```moo",
    "$sub:phrase(text, options)",
    "```",
    "",
    "Options:",
    "",
    "- `'strip_period` - Remove trailing period",
    "- `'initial_lowercase` - Lowercase first character",
    "",
    "Example:",
    "",
    "```moo",
    "result = $sub:phrase(\"Hello world.\", {'strip_period, 'initial_lowercase});",
    "\"Result: hello world\";",
    "```",
    "",
    "## Article Substitutions",
    "",
    "Articles (a, an, the) are determined by the object's noun properties and the builder's template choice.",
    "Article substitutions render both the article and the binding's name (e.g., `{the d}` → \"the sword\"). Proper nouns or self-targets drop the article.",
    "",
    "### Indefinite Articles (a/an)",
    "",
    "```moo",
    "$sub:a('object_name)   # Returns \"a\" or \"an\" (lowercase)",
    "$sub:ac('object_name)  # Returns \"A\" or \"An\" (capitalized)",
    "```",
    "",
    "Returns empty string if:",
    "- The object is a proper noun (is_proper_noun() returns true)",
    "- The object is plural (is_plural() returns true)",
    "",
    "Example:",
    "```moo",
    "sword = #123;  # countable, not proper noun, singular",
    "msg = {$sub:a('sword), \" \", $sub:binding('sword), \" glints.\"};",
    "# Renders as: \"a sword glints.\" or \"an ornate sword glints.\"",
    "```",
    "",
    "### Definite Article (the)",
    "",
    "```moo",
    "$sub:the('object_name)   # Returns \"the\" (lowercase)",
    "$sub:thec('object_name)  # Returns \"The\" (capitalized)",
    "```",
    "",
    "Returns empty string if the object is a proper noun (is_proper_noun() returns true).",
    "",
    "Example:",
    "```moo",
    "msg = {$sub:the('sword), \" \", $sub:binding('sword), \" is sharp.\"};",
    "# Renders as: \"the sword is sharp.\"",
    "```",
    "",
    "### The a_or_an() Helper",
    "",
    "Determines whether a word should use \"a\" or \"an\" with special handling for u-words:",
    "",
    "```moo",
    "article = $sub:a_or_an(\"unicycle\");  # Returns \"a\" (silent u)",
    "article = $sub:a_or_an(\"ukulele\");   # Returns \"an\" (pronounced u)",
    "article = $sub:a_or_an(\"apple\");     # Returns \"an\"",
    "article = $sub:a_or_an(\"banana\");    # Returns \"a\"",
    "```",
    "",
    "Used internally by the article system but can be called directly if needed.",
    "",
    "## Generic Context Bindings",
    "",
    "The `binding()` verb allows substitution of arbitrary values from context, supporting any context type that implements a `get_binding()` method.",
    "",
    "### Usage",
    "",
    "```moo",
    "msg = {$sub:nc(), \" heads \", $sub:binding('direction), \".\"}",
    "```",
    "",
    "### How It Works",
    "",
    "When rendered, `$sub:binding('direction)` calls `context:get_binding('direction)` to fetch the value.",
    "The context can be any flyweight (event, movement context, etc.) that implements:",
    "",
    "```moo",
    "verb get_binding (this none this)",
    "  {name} = args;",
    "  if (name == 'direction) return this.direction; endif",
    "  \"... return other bindings ...\";",
    "endverb",
    "```",
    "",
    "### Capitalized Variant",
    "",
    "Use `$sub:bindingc()` to capitalize the result.",
    "",
    "### Missing Bindings",
    "",
    "If `get_binding()` returns false or the method doesn't exist, the substitution returns `<no-binding>`.",
    "",
    "## Technical Details",
    "",
    "- All substitution verbs use wildcard matching (e.g., `\"n* nc*\"`) to handle variations",
    "- Capitalization is controlled by checking for `\"c\"` in the verb name",
    "- The flyweight's `.capitalize` property is checked during rendering",
    "- Events are composed of lists that may contain strings, flyweights, or other content",
    "- The system recurses through content, evaluating each substitution flyweight it encounters",
    "- Generic bindings allow substitution from any context implementing the `get_binding()` protocol",
    ""
  };

  verb render_as (this none this) owner: HACKER flags: "rxd"
    {render_for, content_type, event} = args;
    content = this:eval_sub(event, render_for);
    return `this.capitalize ! E_PROPNF => false' ? content:capitalize() | content;
  endverb

  verb compose (this none this) owner: HACKER flags: "rxd"
    {render_for, content_type, event} = args;
    content = this:eval_sub(event, render_for);
    return `this.capitalize ! E_PROPNF => false' ? content:capitalize() | content;
  endverb

  verb phrase (this none this) owner: HACKER flags: "rxd"
    {text, ?options = []} = args;
    typeof(text) == STR || return "";
    strip_period = false;
    initial_lowercase = false;
    if (typeof(options) == LIST)
      strip_period = 'strip_period in options;
      initial_lowercase = 'initial_lowercase in options;
    endif
    if (strip_period && length(text) && text[length(text)] == ".")
      text = text[1..length(text) - 1];
    endif
    if (initial_lowercase && length(text))
      first = text[1..1]:lowercase();
      text = first + (length(text) >= 2 ? text[2..$] | "");
    endif
    return text;
  endverb

  verb "self_alt self_altc" (this none this) owner: HACKER flags: "rxd"
    capitalize = verb[length(verb)] == "c";
    {for_self, for_alt} = args;
    return <this, .type = 'self_alt, .capitalize = capitalize, .for_self = for_self, .for_others = for_alt>;
  endverb

  verb eval_sub (this none this) owner: HACKER flags: "rxd"
    {event, render_for} = args;
    this.type == 'actor && return this:name_sub(event.actor, render_for);
    this.type == 'location && return this:name_sub(event.actor.location, render_for);
    this.type == 'this && return this:name_sub(event.this_obj, render_for);
    this.type == 'dobj && return this:name_sub(event.dobj, render_for);
    this.type == 'iobj && return this:name_sub(event.iobj, render_for);
    this.type == 'subject && return event.actor == render_for ? "you" | event.actor:pronoun_subject();
    this.type == 'object && return event.actor == render_for ? "you" | event.actor:pronoun_object();
    this.type == 'pos_adj && return event.actor == render_for ? "your" | event.actor:pronoun_possessive('adj);
    this.type == 'pos_noun && return event.actor == render_for ? "yours" | event.actor:pronoun_possessive('noun);
    this.type == 'reflexive && return event.actor == render_for ? "yourself" | event.actor:pronoun_reflexive();
    this.type == 'dobj_subject && return valid(event.dobj) ? event.dobj == render_for ? "you" | event.dobj:pronoun_subject() | "<no-dobj>";
    this.type == 'dobj_object && return valid(event.dobj) ? event.dobj == render_for ? "you" | event.dobj:pronoun_object() | "<no-dobj>";
    this.type == 'dobj_pos_adj && return valid(event.dobj) ? event.dobj == render_for ? "your" | event.dobj:pronoun_possessive('adj) | "<no-dobj>";
    this.type == 'dobj_pos_noun && return valid(event.dobj) ? event.dobj == render_for ? "yours" | event.dobj:pronoun_possessive('noun) | "<no-dobj>";
    this.type == 'dobj_reflexive && return valid(event.dobj) ? event.dobj == render_for ? "yourself" | event.dobj:pronoun_reflexive() | "<no-dobj>";
    this.type == 'iobj_subject && return valid(event.iobj) ? event.iobj == render_for ? "you" | event.iobj:pronoun_subject() | "<no-iobj>";
    this.type == 'iobj_object && return valid(event.iobj) ? event.iobj == render_for ? "you" | event.iobj:pronoun_object() | "<no-iobj>";
    this.type == 'iobj_pos_adj && return valid(event.iobj) ? event.iobj == render_for ? "your" | event.iobj:pronoun_possessive('adj) | "<no-iobj>";
    this.type == 'iobj_pos_noun && return valid(event.iobj) ? event.iobj == render_for ? "yours" | event.iobj:pronoun_possessive('noun) | "<no-iobj>";
    this.type == 'iobj_reflexive && return valid(event.iobj) ? event.iobj == render_for ? "yourself" | event.iobj:pronoun_reflexive() | "<no-iobj>";
    if (this.type == 'verb_be)
      return event.actor == render_for ? "are" | event.actor:pronouns().verb_be;
    endif
    if (this.type == 'verb_have)
      return event.actor == render_for ? "have" | event.actor:pronouns().verb_have;
    endif
    if (this.type == 'verb_look)
      return event.actor == render_for ? "look" | (event.actor:pronouns().is_plural ? "look" | "looks");
    endif
    if (this.type == 'dobj_verb_be)
      return valid(event.dobj) ? event.dobj == render_for ? "are" | event.dobj:pronouns().verb_be | "<no-dobj>";
    endif
    if (this.type == 'dobj_verb_have)
      return valid(event.dobj) ? event.dobj == render_for ? "have" | event.dobj:pronouns().verb_have | "<no-dobj>";
    endif
    if (this.type == 'dobj_verb_look)
      return valid(event.dobj) ? event.dobj == render_for ? "look" | (event.dobj:pronouns().is_plural ? "look" | "looks") | "<no-dobj>";
    endif
    if (this.type == 'iobj_verb_be)
      return valid(event.iobj) ? event.iobj == render_for ? "are" | event.iobj:pronouns().verb_be | "<no-iobj>";
    endif
    if (this.type == 'iobj_verb_have)
      return valid(event.iobj) ? event.iobj == render_for ? "have" | event.iobj:pronouns().verb_have | "<no-iobj>";
    endif
    if (this.type == 'iobj_verb_look)
      return valid(event.iobj) ? event.iobj == render_for ? "look" | (event.iobj:pronouns().is_plural ? "look" | "looks") | "<no-iobj>";
    endif
    if (this.type == 'self_alt)
      value = event.actor == render_for ? this.for_self | this.for_others;
      "Recursively evaluate if value is a substitution flyweight";
      if (typeof(value) == FLYWEIGHT && `value.type ! E_PROPNF => false')
        return value:eval_sub(event, render_for);
      endif
      return value;
    endif
    if (this.type == 'binding)
      binding_value = `event:get_binding(this.binding_name) ! E_VERBNF, E_PROPNF => false';
      if (binding_value == false)
        return "<no-binding>";
      endif
      "If binding is an object and matches render_for, return 'you'";
      if (typeof(binding_value) == OBJ && binding_value == render_for)
        return "you";
      endif
      "Try to get name, fall back to string representation";
      name = `binding_value:name() ! E_VERBNF => tostr(binding_value)';
      return name;
    endif
    if (this.type == 'article_a)
      binding_value = `event:get_binding(this.binding_name) ! E_VERBNF, E_PROPNF => false';
      if (binding_value == false || typeof(binding_value) != OBJ)
        return "";
      endif
      capitalize_name = `this.capitalize_binding ! E_PROPNF => false';
      is_self = binding_value == render_for;
      is_proper = `binding_value:is_proper_noun() ! E_VERBNF => false';
      is_plural = `binding_value:is_plural() ! E_VERBNF => false';
      name = is_self ? "you" | `binding_value:name() ! E_VERBNF => tostr(binding_value)';
      if (is_proper || is_plural || is_self)
        article = "";
      else
        "singular countable - need a/an";
        article = this:a_or_an(name);
      endif
      if (this.capitalize)
        if (length(article))
          article = article:capitalize();
        endif
      endif
      if (capitalize_name)
        if (length(name))
          name = name:capitalize();
        endif
      endif
      return length(article) ? article + " " + name | name;
    endif
    if (this.type == 'article_the)
      binding_value = `event:get_binding(this.binding_name) ! E_VERBNF, E_PROPNF => false';
      if (binding_value == false || typeof(binding_value) != OBJ)
        return "";
      endif
      capitalize_name = `this.capitalize_binding ! E_PROPNF => false';
      is_self = binding_value == render_for;
      is_proper = `binding_value:is_proper_noun() ! E_VERBNF => false';
      article = (is_proper || is_self) ? "" | "the";
      name = is_self ? "you" | `binding_value:name() ! E_VERBNF => tostr(binding_value)';
      if (this.capitalize)
        if (length(article))
          article = article:capitalize();
        endif
      endif
      if (capitalize_name)
        if (length(name))
          name = name:capitalize();
        endif
      endif
      return length(article) ? article + " " + name | name;
    endif
    return "<invalid-sub>";
  endverb

  verb name_sub (this none this) owner: HACKER flags: "rxd"
    {who, render_for} = args;
    if (who == render_for)
      return "you";
    else
      return `who:name() ! E_VERBNF => who.name';
    endif
  endverb

  verb "d*c" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    return <this, .type = 'dobj, .capitalize = capitalize>;
  endverb

  verb "i*c" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    return <this, .type = 'iobj, .capitalize = capitalize>;
  endverb

  verb "l*c" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    return <this, .type = 'location, .capitalize = capitalize>;
  endverb

  verb "n*c" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    return <this, .type = 'actor, .capitalize = capitalize>;
  endverb

  verb "o*c o*_dobj o*_iobj oc*_dobj oc*_iobj" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    if (verb:ends_with("_dobj"))
      type = 'dobj_object;
    elseif (verb:ends_with("_iobj"))
      type = 'iobj_object;
    else
      type = 'object;
    endif
    return <this, .type = type, .capitalize = capitalize>;
  endverb

  verb "p*c p*_dobj p*_iobj pc*_dobj pc*_iobj" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    if (verb:ends_with("_dobj"))
      type = 'dobj_pos_adj;
    elseif (verb:ends_with("_iobj"))
      type = 'iobj_pos_adj;
    else
      type = 'pos_adj;
    endif
    return <this, .type = type, .capitalize = capitalize>;
  endverb

  verb "q*c q*_dobj q*_iobj qc*_dobj qc*_iobj" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    if (verb:ends_with("_dobj"))
      type = 'dobj_pos_noun;
    elseif (verb:ends_with("_iobj"))
      type = 'iobj_pos_noun;
    else
      type = 'pos_noun;
    endif
    return <this, .type = type, .capitalize = capitalize>;
  endverb

  verb "r*c r*_dobj r*_iobj rc*_dobj rc*_iobj" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    if (verb:ends_with("_dobj"))
      type = 'dobj_reflexive;
    elseif (verb:ends_with("_iobj"))
      type = 'iobj_reflexive;
    else
      type = 'reflexive;
    endif
    return <this, .type = type, .capitalize = capitalize>;
  endverb

  verb "s*c s*_dobj s*_iobj sc*_dobj sc*_iobj" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    if (verb:ends_with("_dobj"))
      type = 'dobj_subject;
    elseif (verb:ends_with("_iobj"))
      type = 'iobj_subject;
    else
      type = 'subject;
    endif
    return <this, .type = type, .capitalize = capitalize>;
  endverb

  verb "t*c*" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    return <this, .type = 'this, .capitalize = capitalize>;
  endverb

  verb "verb_be verb_be_dobj verb_be_iobj" (this none this) owner: HACKER flags: "rxd"
    "Verb conjugation for 'be' (is/are).";
    if (verb:ends_with("_dobj"))
      type = 'dobj_verb_be;
    elseif (verb:ends_with("_iobj"))
      type = 'iobj_verb_be;
    else
      type = 'verb_be;
    endif
    return <this, .type = type>;
  endverb

  verb "verb_have verb_have_dobj verb_have_iobj" (this none this) owner: HACKER flags: "rxd"
    "Verb conjugation for 'have' (has/have).";
    if (verb:ends_with("_dobj"))
      type = 'dobj_verb_have;
    elseif (verb:ends_with("_iobj"))
      type = 'iobj_verb_have;
    else
      type = 'verb_have;
    endif
    return <this, .type = type>;
  endverb

  verb "verb_look verb_look_dobj verb_look_iobj" (this none this) owner: HACKER flags: "rxd"
    "Verb conjugation for 'look' (look/looks).";
    if (verb:ends_with("_dobj"))
      type = 'dobj_verb_look;
    elseif (verb:ends_with("_iobj"))
      type = 'iobj_verb_look;
    else
      type = 'verb_look;
    endif
    return <this, .type = type>;
  endverb

  verb "binding*" (this none this) owner: HACKER flags: "rxd"
    "Generic context binding - fetches arbitrary values from context via get_binding().";
    capitalize = index(verb, "c") != 0;
    {binding_name} = args;
    return <this, .type = 'binding, .binding_name = binding_name, .capitalize = capitalize>;
  endverb

  verb "a*c" (this none this) owner: HACKER flags: "rxd"
    "Get indefinite article (a/an) for a binding. Returns article flyweight.";
    capitalize_article = index(verb, "c") != 0;
    {binding_name} = args;
    name_str = tostr(binding_name);
    capitalize_binding = name_str:ends_with("c") && length(name_str) > 1;
    if (capitalize_binding)
      binding_name = tosym(name_str[1..length(name_str) - 1]);
    endif
    return <this, .type = 'article_a, .binding_name = binding_name, .capitalize = capitalize_article, .capitalize_binding = capitalize_binding>;
  endverb

  verb "the*c" (this none this) owner: HACKER flags: "rxd"
    "Get definite article (the) for a binding. Returns article flyweight.";
    capitalize_article = index(verb, "c") != 0;
    {binding_name} = args;
    name_str = tostr(binding_name);
    capitalize_binding = name_str:ends_with("c") && length(name_str) > 1;
    if (capitalize_binding)
      binding_name = tosym(name_str[1..length(name_str) - 1]);
    endif
    return <this, .type = 'article_the, .binding_name = binding_name, .capitalize = capitalize_article, .capitalize_binding = capitalize_binding>;
  endverb

  verb a_or_an (this none this) owner: HACKER flags: "rxd"
    "Return 'a' or 'an' depending on the word. Handles exceptions like 'unicycle'.";
    {word} = args;
    if (typeof(word) != STR || !length(word))
      return "a";
    endif
    "Check first letter";
    if (index("aeiou", word[1]))
      article = "an";
      "except for 'u' words like 'unicycle', 'union'";
      if (word[1] == "u" && length(word) > 2 && word[2] == "n")
        if (index("aeiou", word[3]) == 0 ||
            (word[3] == "i" && length(word) > 3 &&
             (index("aeioubcghqwyz", word[4]) ||
              (length(word) > 4 && index("eiy", word[5])))))
          article = "a";
        endif
      endif
    else
      article = "a";
    endif
    return article;
  endverb

  verb test_a_or_an_vowels (this none this) owner: HACKER flags: "rxd"
    "Test a_or_an() returns 'an' for vowel starters.";
    this:a_or_an("apple") == "an" || return E_ASSERT;
    this:a_or_an("egg") == "an" || return E_ASSERT;
    this:a_or_an("igloo") == "an" || return E_ASSERT;
    this:a_or_an("orange") == "an" || return E_ASSERT;
    this:a_or_an("umbrella") == "an" || return E_ASSERT;
    return true;
  endverb

  verb test_a_or_an_consonants (this none this) owner: HACKER flags: "rxd"
    "Test a_or_an() returns 'a' for consonant starters.";
    this:a_or_an("banana") == "a" || return E_ASSERT;
    this:a_or_an("cat") == "a" || return E_ASSERT;
    this:a_or_an("dog") == "a" || return E_ASSERT;
    return true;
  endverb

  verb test_a_or_an_u_silent (this none this) owner: HACKER flags: "rxd"
    "Test a_or_an() with 'u' words that have silent 'u' sound.";
    this:a_or_an("unicycle") == "a" || return E_ASSERT;
    this:a_or_an("union") == "a" || return E_ASSERT;
    this:a_or_an("university") == "a" || return E_ASSERT;
    this:a_or_an("unit") == "a" || return E_ASSERT;
    return true;
  endverb

  verb test_a_or_an_u_pronounced (this none this) owner: HACKER flags: "rxd"
    "Test a_or_an() with 'u' words that have pronounced 'u' sound.";
    this:a_or_an("ukulele") == "an" || return E_ASSERT;
    return true;
  endverb

  verb test_a_or_an_edge_cases (this none this) owner: HACKER flags: "rxd"
    "Test a_or_an() with edge cases.";
    this:a_or_an("") == "a" || return E_ASSERT;
    this:a_or_an("x") == "a" || return E_ASSERT;
    this:a_or_an("a") == "an" || return E_ASSERT;
    return true;
  endverb

  verb test_article_a_creation (this none this) owner: HACKER flags: "rxd"
    "Test a() article flyweight creation.";
    fw = this:a('test_binding);
    typeof(fw) != FLYWEIGHT && return E_TYPE;
    fw.type != 'article_a && return E_ASSERT;
    fw.binding_name != 'test_binding && return E_ASSERT;
    fw.capitalize != false && return E_ASSERT;
    return true;
  endverb

  verb test_article_ac_creation (this none this) owner: HACKER flags: "rxd"
    "Test ac() capitalized article flyweight.";
    fwc = this:ac('test_binding);
    fwc.type != 'article_a && return E_ASSERT;
    fwc.capitalize != true && return E_ASSERT;
    return true;
  endverb

  verb test_article_the_creation (this none this) owner: HACKER flags: "rxd"
    "Test the() article flyweight creation.";
    fw = this:the('test_binding);
    typeof(fw) != FLYWEIGHT && return E_TYPE;
    fw.type != 'article_the && return E_ASSERT;
    fw.binding_name != 'test_binding && return E_ASSERT;
    fw.capitalize != false && return E_ASSERT;
    `fw.capitalize_binding ! E_PROPNF => false' != false && return E_ASSERT;
    return true;
  endverb

  verb test_article_thec_creation (this none this) owner: HACKER flags: "rxd"
    "Test thec() capitalized article flyweight.";
    fwc = this:thec('test_binding);
    fwc.type != 'article_the && return E_ASSERT;
    fwc.capitalize != true && return E_ASSERT;
    `fwc.capitalize_binding ! E_PROPNF => false' != false && return E_ASSERT;
    return true;
  endverb

  verb test_article_the_eval (this none this) owner: HACKER flags: "rxd"
    "Test article_the() renders with binding name.";
    event = $event:mk_test(this):with_dobj(this);
    fw = this:the('d);
    result = fw:eval_sub(event, #0);
    result != "the " + this.name && return E_ASSERT;
    return true;
  endverb

  verb test_article_a_eval (this none this) owner: HACKER flags: "rxd"
    "Test article_a() renders with binding name.";
    event = $event:mk_test(this):with_dobj(this);
    fw = this:a('d);
    result = fw:eval_sub(event, #0);
    expected_prefix = this:a_or_an(this.name);
    result != expected_prefix + " " + this.name && return E_ASSERT;
    return true;
  endverb

  verb test_article_with_capitalized_binding (this none this) owner: HACKER flags: "rxd"
    "Test binding suffix c capitalizes the noun, not the article.";
    event = $event:mk_test(this):with_dobj(this);
    fw = this:the('dc);
    result = fw:eval_sub(event, #0);
    expected = "the " + this.name:capitalize();
    result != expected && return E_ASSERT("Expected '" + expected + "', got '" + result + "'");
    return true;
  endverb

  verb test_binding_creation (this none this) owner: HACKER flags: "rxd"
    "Test binding() flyweight creation.";
    fw = this:binding('test_name);
    typeof(fw) != FLYWEIGHT && return E_TYPE;
    fw.type != 'binding && return E_ASSERT;
    fw.binding_name != 'test_name && return E_ASSERT;
    return true;
  endverb

  verb test_bindingc_creation (this none this) owner: HACKER flags: "rxd"
    "Test bindingc() capitalized binding flyweight.";
    fwc = this:bindingc('test_name);
    fwc.type != 'binding && return E_ASSERT;
    fwc.capitalize != true && return E_ASSERT;
    return true;
  endverb

  verb test_self_alt_creation (this none this) owner: HACKER flags: "rxd"
    "Test self_alt() flyweight creation.";
    fw = this:self_alt("for_self", "for_others");
    typeof(fw) != FLYWEIGHT && return E_TYPE;
    fw.type != 'self_alt && return E_ASSERT;
    fw.for_self != "for_self" && return E_ASSERT;
    fw.for_others != "for_others" && return E_ASSERT;
    fw.capitalize != false && return E_ASSERT;
    return true;
  endverb

  verb test_self_altc_creation (this none this) owner: HACKER flags: "rxd"
    "Test self_altc() capitalized self-alt flyweight.";
    fwc = this:self_altc("For_self", "For_others");
    fwc.type != 'self_alt && return E_ASSERT;
    fwc.capitalize != true && return E_ASSERT;
    return true;
  endverb

  verb test_name_subs_actor (this none this) owner: HACKER flags: "rxd"
    "Test n() and nc() actor name substitutions.";
    fw = this:n();
    fw.type != 'actor && return E_ASSERT;
    fw.capitalize != false && return E_ASSERT;
    fwc = this:nc();
    fwc.type != 'actor && return E_ASSERT;
    fwc.capitalize != true && return E_ASSERT;
    return true;
  endverb

  verb test_name_subs_objects (this none this) owner: HACKER flags: "rxd"
    "Test d/i/l/t object name substitutions.";
    fwd = this:d();
    fwd.type != 'dobj && return E_ASSERT;
    fwi = this:i();
    fwi.type != 'iobj && return E_ASSERT;
    fwl = this:l();
    fwl.type != 'location && return E_ASSERT;
    fwt = this:t();
    fwt.type != 'this && return E_ASSERT;
    return true;
  endverb

  verb test_pronouns_actor (this none this) owner: HACKER flags: "rxd"
    "Test actor pronoun substitutions.";
    fw_s = this:s();
    fw_s.type != 'subject && return E_ASSERT;
    fw_sc = this:sc();
    fw_sc.type != 'subject && return E_ASSERT;
    fw_sc.capitalize != true && return E_ASSERT;
    fw_o = this:o();
    fw_o.type != 'object && return E_ASSERT;
    fw_p = this:p();
    fw_p.type != 'pos_adj && return E_ASSERT;
    fw_q = this:q();
    fw_q.type != 'pos_noun && return E_ASSERT;
    fw_r = this:r();
    fw_r.type != 'reflexive && return E_ASSERT;
    return true;
  endverb

  verb test_pronouns_dobj (this none this) owner: HACKER flags: "rxd"
    "Test direct object pronoun substitutions.";
    fw_s = this:s_dobj();
    fw_s.type != 'dobj_subject && return E_ASSERT;
    fw_o = this:o_dobj();
    fw_o.type != 'dobj_object && return E_ASSERT;
    fw_p = this:p_dobj();
    fw_p.type != 'dobj_pos_adj && return E_ASSERT;
    fw_q = this:q_dobj();
    fw_q.type != 'dobj_pos_noun && return E_ASSERT;
    fw_r = this:r_dobj();
    fw_r.type != 'dobj_reflexive && return E_ASSERT;
    return true;
  endverb

  verb test_pronouns_iobj (this none this) owner: HACKER flags: "rxd"
    "Test indirect object pronoun substitutions.";
    fw_s = this:s_iobj();
    fw_s.type != 'iobj_subject && return E_ASSERT;
    fw_o = this:o_iobj();
    fw_o.type != 'iobj_object && return E_ASSERT;
    fw_p = this:p_iobj();
    fw_p.type != 'iobj_pos_adj && return E_ASSERT;
    fw_q = this:q_iobj();
    fw_q.type != 'iobj_pos_noun && return E_ASSERT;
    fw_r = this:r_iobj();
    fw_r.type != 'iobj_reflexive && return E_ASSERT;
    return true;
  endverb

  verb test_verb_conjugation_be (this none this) owner: HACKER flags: "rxd"
    "Test verb_be() conjugation flyweights.";
    fw_be = this:verb_be();
    fw_be.type != 'verb_be && return E_ASSERT;
    fw_be_d = this:verb_be_dobj();
    fw_be_d.type != 'dobj_verb_be && return E_ASSERT;
    fw_be_i = this:verb_be_iobj();
    fw_be_i.type != 'iobj_verb_be && return E_ASSERT;
    return true;
  endverb

  verb test_verb_conjugation_have (this none this) owner: HACKER flags: "rxd"
    "Test verb_have() conjugation flyweights.";
    fw_have = this:verb_have();
    fw_have.type != 'verb_have && return E_ASSERT;
    fw_have_d = this:verb_have_dobj();
    fw_have_d.type != 'dobj_verb_have && return E_ASSERT;
    fw_have_i = this:verb_have_iobj();
    fw_have_i.type != 'iobj_verb_have && return E_ASSERT;
    return true;
  endverb

  verb test_verb_conjugation_look (this none this) owner: HACKER flags: "rxd"
    "Test verb_look() conjugation flyweights.";
    fw_look = this:verb_look();
    fw_look.type != 'verb_look && return E_ASSERT;
    fw_look_d = this:verb_look_dobj();
    fw_look_d.type != 'dobj_verb_look && return E_ASSERT;
    fw_look_i = this:verb_look_iobj();
    fw_look_i.type != 'iobj_verb_look && return E_ASSERT;
    return true;
  endverb

  verb test_phrase_strip_period (this none this) owner: HACKER flags: "rxd"
    "Test phrase() with strip_period option.";
    result = this:phrase("Hello world.", {'strip_period});
    result != "Hello world" && return E_ASSERT;
    return true;
  endverb

  verb test_phrase_initial_lowercase (this none this) owner: HACKER flags: "rxd"
    "Test phrase() with initial_lowercase option.";
    result = this:phrase("Hello world", {'initial_lowercase});
    result != "hello world" && return E_ASSERT;
    return true;
  endverb

  verb test_phrase_both_options (this none this) owner: HACKER flags: "rxd"
    "Test phrase() with both strip_period and initial_lowercase.";
    result = this:phrase("Hello world.", {'strip_period, 'initial_lowercase});
    result != "hello world" && return E_ASSERT;
    return true;
  endverb

  verb test_phrase_no_options (this none this) owner: HACKER flags: "rxd"
    "Test phrase() with no options returns unchanged text.";
    result = this:phrase("Hello world.");
    result != "Hello world." && return E_ASSERT;
    return true;
  endverb

  verb test_phrase_empty_string (this none this) owner: HACKER flags: "rxd"
    "Test phrase() with empty string returns empty.";
    result = this:phrase("");
    result != "" && return E_ASSERT;
    return true;
  endverb
endobject
