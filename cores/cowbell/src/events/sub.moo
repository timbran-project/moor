object SUB [
  import_export_id -> "sub",
  import_export_hierarchy -> {"events"}
]
  name: "Substitutions Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Flyweight delegate and factory for template substitution in events.";
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
    "Article substitutions render both the article and the binding's name (e.g., `{the d}` \u2192 \"the sword\"). Proper nouns or self-targets drop the article.",
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

  method is_proper_noun owner: ARCH_WIZARD
    "Return false so article tests work correctly.";
    return false;
  endmethod

  method render_as owner: HACKER
    {render_for, content_type, event} = args;
    content = this:eval_sub(event, render_for);
    return `this.capitalize ! E_PROPNF => false' ? content:capitalize() | content;
  endmethod

  method compose owner: HACKER
    {render_for, content_type, event} = args;
    content = this:eval_sub(event, render_for);
    return `this.capitalize ! E_PROPNF => false' ? content:capitalize() | content;
  endmethod

  method phrase owner: HACKER
    {text, ?options = []} = args;
    typeof(text) != TYPE_STR && return "";
    strip_period = typeof(options) == TYPE_LIST && 'strip_period in options;
    initial_lowercase = typeof(options) == TYPE_LIST && 'initial_lowercase in options;
    strip_period && length(text) && text[$] == "." && (text = text[1..$ - 1]);
    initial_lowercase && length(text) && (text = text[1]:lowercase() + (length(text) >= 2 ? text[2..$] | ""));
    return text;
  endmethod

  method "self_alt self_altc" owner: HACKER
    capitalize = verb[length(verb)] == "c";
    {for_self, for_alt} = args;
    return <this, .type = 'self_alt, .capitalize = capitalize, .for_self = for_self, .for_others = for_alt>;
  endmethod

  method eval_sub owner: HACKER
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
    this.type == 'dobj_subject && return typeof(event.dobj) == TYPE_OBJ && valid(event.dobj) ? event.dobj == render_for ? "you" | event.dobj:pronoun_subject() | "<no-dobj>";
    this.type == 'dobj_object && return typeof(event.dobj) == TYPE_OBJ && valid(event.dobj) ? event.dobj == render_for ? "you" | event.dobj:pronoun_object() | "<no-dobj>";
    this.type == 'dobj_pos_adj && return typeof(event.dobj) == TYPE_OBJ && valid(event.dobj) ? event.dobj == render_for ? "your" | event.dobj:pronoun_possessive('adj) | "<no-dobj>";
    this.type == 'dobj_pos_noun && return typeof(event.dobj) == TYPE_OBJ && valid(event.dobj) ? event.dobj == render_for ? "yours" | event.dobj:pronoun_possessive('noun) | "<no-dobj>";
    this.type == 'dobj_reflexive && return typeof(event.dobj) == TYPE_OBJ && valid(event.dobj) ? event.dobj == render_for ? "yourself" | event.dobj:pronoun_reflexive() | "<no-dobj>";
    this.type == 'iobj_subject && return typeof(event.iobj) == TYPE_OBJ && valid(event.iobj) ? event.iobj == render_for ? "you" | event.iobj:pronoun_subject() | "<no-iobj>";
    this.type == 'iobj_object && return typeof(event.iobj) == TYPE_OBJ && valid(event.iobj) ? event.iobj == render_for ? "you" | event.iobj:pronoun_object() | "<no-iobj>";
    this.type == 'iobj_pos_adj && return typeof(event.iobj) == TYPE_OBJ && valid(event.iobj) ? event.iobj == render_for ? "your" | event.iobj:pronoun_possessive('adj) | "<no-iobj>";
    this.type == 'iobj_pos_noun && return typeof(event.iobj) == TYPE_OBJ && valid(event.iobj) ? event.iobj == render_for ? "yours" | event.iobj:pronoun_possessive('noun) | "<no-iobj>";
    this.type == 'iobj_reflexive && return typeof(event.iobj) == TYPE_OBJ && valid(event.iobj) ? event.iobj == render_for ? "yourself" | event.iobj:pronoun_reflexive() | "<no-iobj>";
    this.type == 'verb_be && return event.actor == render_for ? "are" | event.actor:pronouns().verb_be;
    this.type == 'verb_have && return event.actor == render_for ? "have" | event.actor:pronouns().verb_have;
    this.type == 'verb_look && return event.actor == render_for ? "look" | event.actor:pronouns().is_plural ? "look" | "looks";
    this.type == 'dobj_verb_be && return typeof(event.dobj) == TYPE_OBJ && valid(event.dobj) ? event.dobj == render_for ? "are" | event.dobj:pronouns().verb_be | "<no-dobj>";
    this.type == 'dobj_verb_have && return typeof(event.dobj) == TYPE_OBJ && valid(event.dobj) ? event.dobj == render_for ? "have" | event.dobj:pronouns().verb_have | "<no-dobj>";
    this.type == 'dobj_verb_look && return typeof(event.dobj) == TYPE_OBJ && valid(event.dobj) ? event.dobj == render_for ? "look" | event.dobj:pronouns().is_plural ? "look" | "looks" | "<no-dobj>";
    this.type == 'iobj_verb_be && return typeof(event.iobj) == TYPE_OBJ && valid(event.iobj) ? event.iobj == render_for ? "are" | event.iobj:pronouns().verb_be | "<no-iobj>";
    this.type == 'iobj_verb_have && return typeof(event.iobj) == TYPE_OBJ && valid(event.iobj) ? event.iobj == render_for ? "have" | event.iobj:pronouns().verb_have | "<no-iobj>";
    this.type == 'iobj_verb_look && return typeof(event.iobj) == TYPE_OBJ && valid(event.iobj) ? event.iobj == render_for ? "look" | event.iobj:pronouns().is_plural ? "look" | "looks" | "<no-iobj>";
    if (this.type == 'self_alt)
      value = event.actor == render_for ? this.for_self | this.for_others;
      typeof(value) == TYPE_FLYWEIGHT && `value.type ! E_PROPNF => false' && return value:eval_sub(event, render_for);
      return value;
    endif
    if (this.type == 'binding)
      binding_value = `event:get_binding(this.binding_name) ! E_VERBNF, E_PROPNF => false';
      binding_value == false && return "<no-binding>";
      typeof(binding_value) == TYPE_OBJ && binding_value == render_for && return "you";
      return `binding_value:name() ! E_VERBNF => tostr(binding_value)';
    endif
    if (this.type == 'article_a)
      binding_value = `event:get_binding(this.binding_name) ! E_VERBNF, E_PROPNF => false';
      binding_value == false || typeof(binding_value) != TYPE_OBJ && return "";
      capitalize_name = `this.capitalize_binding ! E_PROPNF => false';
      is_self = binding_value == render_for;
      is_proper = `binding_value:is_proper_noun() ! E_VERBNF => false';
      is_plural = `binding_value:is_plural() ! E_VERBNF => false';
      name = is_self ? "you" | `binding_value:name() ! E_VERBNF => tostr(binding_value)';
      article = is_proper || is_plural || is_self ? "" | this:a_or_an(name);
      this.capitalize && length(article) && (article = article:capitalize());
      capitalize_name && length(name) && (name = name:capitalize());
      return length(article) ? article + " " + name | name;
    endif
    if (this.type == 'article_the)
      binding_value = `event:get_binding(this.binding_name) ! E_VERBNF, E_PROPNF => false';
      binding_value == false || typeof(binding_value) != TYPE_OBJ && return "";
      capitalize_name = `this.capitalize_binding ! E_PROPNF => false';
      is_self = binding_value == render_for;
      is_proper = `binding_value:is_proper_noun() ! E_VERBNF => false';
      article = is_proper || is_self ? "" | "the";
      name = is_self ? "you" | `binding_value:name() ! E_VERBNF => tostr(binding_value)';
      this.capitalize && length(article) && (article = article:capitalize());
      capitalize_name && length(name) && (name = name:capitalize());
      return length(article) ? article + " " + name | name;
    endif
    return "<invalid-sub>";
  endmethod

  method name_sub owner: HACKER
    {who, render_for} = args;
    return who == render_for ? "you" | `who:name() ! E_VERBNF => who.name';
  endmethod

  method "d*c" owner: HACKER
    capitalize = index(verb, "c") != 0;
    return <this, .type = 'dobj, .capitalize = capitalize>;
  endmethod

  method "i*c" owner: HACKER
    capitalize = index(verb, "c") != 0;
    return <this, .type = 'iobj, .capitalize = capitalize>;
  endmethod

  method "l*c" owner: HACKER
    capitalize = index(verb, "c") != 0;
    return <this, .type = 'location, .capitalize = capitalize>;
  endmethod

  method "n*c" owner: HACKER
    capitalize = index(verb, "c") != 0;
    return <this, .type = 'actor, .capitalize = capitalize>;
  endmethod

  method "o*c o*_dobj o*_iobj oc*_dobj oc*_iobj" owner: HACKER
    capitalize = index(verb, "c") != 0;
    type = verb:ends_with("_dobj") ? 'dobj_object | verb:ends_with("_iobj") ? 'iobj_object | 'object;
    return <this, .type = type, .capitalize = capitalize>;
  endmethod

  method "p*c p*_dobj p*_iobj pc*_dobj pc*_iobj" owner: HACKER
    capitalize = index(verb, "c") != 0;
    type = verb:ends_with("_dobj") ? 'dobj_pos_adj | verb:ends_with("_iobj") ? 'iobj_pos_adj | 'pos_adj;
    return <this, .type = type, .capitalize = capitalize>;
  endmethod

  method "q*c q*_dobj q*_iobj qc*_dobj qc*_iobj" owner: HACKER
    capitalize = index(verb, "c") != 0;
    type = verb:ends_with("_dobj") ? 'dobj_pos_noun | verb:ends_with("_iobj") ? 'iobj_pos_noun | 'pos_noun;
    return <this, .type = type, .capitalize = capitalize>;
  endmethod

  method "r*c r*_dobj r*_iobj rc*_dobj rc*_iobj" owner: HACKER
    capitalize = index(verb, "c") != 0;
    type = verb:ends_with("_dobj") ? 'dobj_reflexive | verb:ends_with("_iobj") ? 'iobj_reflexive | 'reflexive;
    return <this, .type = type, .capitalize = capitalize>;
  endmethod

  method "s*c s*_dobj s*_iobj sc*_dobj sc*_iobj" owner: HACKER
    capitalize = index(verb, "c") != 0;
    type = verb:ends_with("_dobj") ? 'dobj_subject | verb:ends_with("_iobj") ? 'iobj_subject | 'subject;
    return <this, .type = type, .capitalize = capitalize>;
  endmethod

  method "t*c*" owner: HACKER
    capitalize = index(verb, "c") != 0;
    return <this, .type = 'this, .capitalize = capitalize>;
  endmethod

  method "verb_be verb_be_dobj verb_be_iobj" owner: HACKER
    "Verb conjugation for 'be' (is/are).";
    type = verb:ends_with("_dobj") ? 'dobj_verb_be | verb:ends_with("_iobj") ? 'iobj_verb_be | 'verb_be;
    return <this, .type = type>;
  endmethod

  method "verb_have verb_have_dobj verb_have_iobj" owner: HACKER
    "Verb conjugation for 'have' (has/have).";
    type = verb:ends_with("_dobj") ? 'dobj_verb_have | verb:ends_with("_iobj") ? 'iobj_verb_have | 'verb_have;
    return <this, .type = type>;
  endmethod

  method "verb_look verb_look_dobj verb_look_iobj" owner: HACKER
    "Verb conjugation for 'look' (look/looks).";
    type = verb:ends_with("_dobj") ? 'dobj_verb_look | verb:ends_with("_iobj") ? 'iobj_verb_look | 'verb_look;
    return <this, .type = type>;
  endmethod

  method "binding*" owner: HACKER
    "Generic context binding - fetches arbitrary values from context via get_binding().";
    capitalize = index(verb, "c") != 0;
    {binding_name} = args;
    return <this, .type = 'binding, .binding_name = binding_name, .capitalize = capitalize>;
  endmethod

  method "a*c" owner: HACKER
    "Get indefinite article (a/an) for a binding. Returns article flyweight.";
    capitalize_article = index(verb, "c") != 0;
    {binding_name} = args;
    name_str = tostr(binding_name);
    capitalize_binding = name_str:ends_with("c") && length(name_str) > 1;
    if (capitalize_binding)
      binding_name = tosym(name_str[1..length(name_str) - 1]);
    endif
    return <this, .type = 'article_a, .binding_name = binding_name, .capitalize = capitalize_article, .capitalize_binding = capitalize_binding>;
  endmethod

  method "the*c" owner: HACKER
    "Get definite article (the) for a binding. Returns article flyweight.";
    capitalize_article = index(verb, "c") != 0;
    {binding_name} = args;
    name_str = tostr(binding_name);
    capitalize_binding = name_str:ends_with("c") && length(name_str) > 1;
    if (capitalize_binding)
      binding_name = tosym(name_str[1..length(name_str) - 1]);
    endif
    return <this, .type = 'article_the, .binding_name = binding_name, .capitalize = capitalize_article, .capitalize_binding = capitalize_binding>;
  endmethod

  method a_or_an owner: HACKER
    "Return 'a' or 'an' depending on the word. Handles exceptions like 'unicycle'.";
    {word} = args;
    typeof(word) != TYPE_STR || !length(word) && return "a";
    first = word[1]:lowercase();
    "Words starting with 'uni' or 'unu' use 'a' (pronounced 'yoo')";
    if (length(word) >= 3 && first == "u" && word[2]:lowercase() == "n" && index("iu", word[3]:lowercase()))
      return "a";
    endif
    return index("aeiou", first) ? "an" | "a";
  endmethod

  method test_a_or_an_vowels owner: HACKER
    "Test a_or_an() returns 'an' for vowel starters.";
    $test_utils:assert_eq(this:a_or_an("apple"), "an", "apple article");
    $test_utils:assert_eq(this:a_or_an("egg"), "an", "egg article");
    $test_utils:assert_eq(this:a_or_an("igloo"), "an", "igloo article");
    $test_utils:assert_eq(this:a_or_an("orange"), "an", "orange article");
    $test_utils:assert_eq(this:a_or_an("umbrella"), "an", "umbrella article");
    return true;
  endmethod

  method test_a_or_an_consonants owner: HACKER
    "Test a_or_an() returns 'a' for consonant starters.";
    $test_utils:assert_eq(this:a_or_an("banana"), "a", "banana article");
    $test_utils:assert_eq(this:a_or_an("cat"), "a", "cat article");
    $test_utils:assert_eq(this:a_or_an("dog"), "a", "dog article");
    return true;
  endmethod

  method test_a_or_an_u_silent owner: HACKER
    "Test a_or_an() with 'u' words that have silent 'u' sound.";
    $test_utils:assert_eq(this:a_or_an("unicycle"), "a", "unicycle article");
    $test_utils:assert_eq(this:a_or_an("union"), "a", "union article");
    $test_utils:assert_eq(this:a_or_an("university"), "a", "university article");
    $test_utils:assert_eq(this:a_or_an("unit"), "a", "unit article");
    return true;
  endmethod

  method test_a_or_an_u_pronounced owner: HACKER
    "Test a_or_an() with 'u' words that have pronounced 'u' sound.";
    $test_utils:assert_eq(this:a_or_an("ukulele"), "an", "ukulele article");
    return true;
  endmethod

  method test_a_or_an_edge_cases owner: HACKER
    "Test a_or_an() with edge cases.";
    $test_utils:assert_eq(this:a_or_an(""), "a", "empty article");
    $test_utils:assert_eq(this:a_or_an("x"), "a", "single consonant article");
    $test_utils:assert_eq(this:a_or_an("a"), "an", "single vowel article");
    return true;
  endmethod

  method test_article_a_creation owner: HACKER
    "Test a() article flyweight creation.";
    fw = this:a('test_binding);
    $test_utils:assert_type(fw, TYPE_FLYWEIGHT, "a() should return flyweight");
    $test_utils:assert_eq(fw.type, 'article_a, "a() type");
    $test_utils:assert_eq(fw.binding_name, 'test_binding, "a() binding");
    $test_utils:assert_false(fw.capitalize, "a() should not capitalize");
    return true;
  endmethod

  method test_article_ac_creation owner: HACKER
    "Test ac() capitalized article flyweight.";
    fwc = this:ac('test_binding);
    $test_utils:assert_eq(fwc.type, 'article_a, "ac() type");
    $test_utils:assert_true(fwc.capitalize, "ac() should capitalize");
    return true;
  endmethod

  method test_article_the_creation owner: HACKER
    "Test the() article flyweight creation.";
    fw = this:the('test_binding);
    $test_utils:assert_type(fw, TYPE_FLYWEIGHT, "the() should return flyweight");
    $test_utils:assert_eq(fw.type, 'article_the, "the() type");
    $test_utils:assert_eq(fw.binding_name, 'test_binding, "the() binding");
    $test_utils:assert_false(fw.capitalize, "the() should not capitalize");
    $test_utils:assert_false(`fw.capitalize_binding ! E_PROPNF => false', "the() should not set capitalize_binding");
    return true;
  endmethod

  method test_article_thec_creation owner: HACKER
    "Test thec() capitalized article flyweight.";
    fwc = this:thec('test_binding);
    $test_utils:assert_eq(fwc.type, 'article_the, "thec() type");
    $test_utils:assert_true(fwc.capitalize, "thec() should capitalize");
    $test_utils:assert_false(`fwc.capitalize_binding ! E_PROPNF => false', "thec() should not set capitalize_binding");
    return true;
  endmethod

  method test_article_the_eval owner: HACKER
    "Test article_the() renders with binding name.";
    event = $event:mk_test(this):with_dobj(this);
    fw = this:the('d);
    result = fw:eval_sub(event, #0);
    $test_utils:assert_eq(result, "the " + this.name, "the() rendered text");
    return true;
  endmethod

  method test_article_a_eval owner: HACKER
    "Test article_a() renders with binding name.";
    event = $event:mk_test(this):with_dobj(this);
    fw = this:a('d);
    result = fw:eval_sub(event, #0);
    expected_prefix = this:a_or_an(this.name);
    $test_utils:assert_eq(result, expected_prefix + " " + this.name, "a() rendered text");
    return true;
  endmethod

  method test_article_with_capitalized_binding owner: HACKER
    "Test binding suffix c capitalizes the noun, not the article.";
    event = $event:mk_test(this):with_dobj(this);
    fw = this:the('dc);
    result = fw:eval_sub(event, #0);
    expected = "the " + this.name:capitalize();
    $test_utils:assert_eq(result, expected, "capitalized binding rendered text");
    return true;
  endmethod

  method test_binding_creation owner: HACKER
    "Test binding() flyweight creation.";
    fw = this:binding('test_name);
    $test_utils:assert_type(fw, TYPE_FLYWEIGHT, "binding() should return flyweight");
    $test_utils:assert_eq(fw.type, 'binding, "binding() type");
    $test_utils:assert_eq(fw.binding_name, 'test_name, "binding() name");
    return true;
  endmethod

  method test_bindingc_creation owner: HACKER
    "Test bindingc() capitalized binding flyweight.";
    fwc = this:bindingc('test_name);
    $test_utils:assert_eq(fwc.type, 'binding, "bindingc() type");
    $test_utils:assert_true(fwc.capitalize, "bindingc() should capitalize");
    return true;
  endmethod

  method test_self_alt_creation owner: HACKER
    "Test self_alt() flyweight creation.";
    fw = this:self_alt("for_self", "for_others");
    $test_utils:assert_type(fw, TYPE_FLYWEIGHT, "self_alt() should return flyweight");
    $test_utils:assert_eq(fw.type, 'self_alt, "self_alt() type");
    $test_utils:assert_eq(fw.for_self, "for_self", "self_alt() self text");
    $test_utils:assert_eq(fw.for_others, "for_others", "self_alt() others text");
    $test_utils:assert_false(fw.capitalize, "self_alt() should not capitalize");
    return true;
  endmethod

  method test_self_altc_creation owner: HACKER
    "Test self_altc() capitalized self-alt flyweight.";
    fwc = this:self_altc("For_self", "For_others");
    $test_utils:assert_eq(fwc.type, 'self_alt, "self_altc() type");
    $test_utils:assert_true(fwc.capitalize, "self_altc() should capitalize");
    return true;
  endmethod

  method test_name_subs_actor owner: HACKER
    "Test n() and nc() actor name substitutions.";
    fw = this:n();
    $test_utils:assert_eq(fw.type, 'actor, "n() type");
    $test_utils:assert_false(fw.capitalize, "n() should not capitalize");
    fwc = this:nc();
    $test_utils:assert_eq(fwc.type, 'actor, "nc() type");
    $test_utils:assert_true(fwc.capitalize, "nc() should capitalize");
    return true;
  endmethod

  method test_name_subs_objects owner: HACKER
    "Test d/i/l/t object name substitutions.";
    fwd = this:d();
    $test_utils:assert_eq(fwd.type, 'dobj, "d() type");
    fwi = this:i();
    $test_utils:assert_eq(fwi.type, 'iobj, "i() type");
    fwl = this:l();
    $test_utils:assert_eq(fwl.type, 'location, "l() type");
    fwt = this:t();
    $test_utils:assert_eq(fwt.type, 'this, "t() type");
    return true;
  endmethod

  method test_pronouns_actor owner: HACKER
    "Test actor pronoun substitutions.";
    fw_s = this:s();
    $test_utils:assert_eq(fw_s.type, 'subject, "s() type");
    fw_sc = this:sc();
    $test_utils:assert_eq(fw_sc.type, 'subject, "sc() type");
    $test_utils:assert_true(fw_sc.capitalize, "sc() should capitalize");
    fw_o = this:o();
    $test_utils:assert_eq(fw_o.type, 'object, "o() type");
    fw_p = this:p();
    $test_utils:assert_eq(fw_p.type, 'pos_adj, "p() type");
    fw_q = this:q();
    $test_utils:assert_eq(fw_q.type, 'pos_noun, "q() type");
    fw_r = this:r();
    $test_utils:assert_eq(fw_r.type, 'reflexive, "r() type");
    return true;
  endmethod

  method test_pronouns_dobj owner: HACKER
    "Test direct object pronoun substitutions.";
    fw_s = this:s_dobj();
    $test_utils:assert_eq(fw_s.type, 'dobj_subject, "s_dobj() type");
    fw_o = this:o_dobj();
    $test_utils:assert_eq(fw_o.type, 'dobj_object, "o_dobj() type");
    fw_p = this:p_dobj();
    $test_utils:assert_eq(fw_p.type, 'dobj_pos_adj, "p_dobj() type");
    fw_q = this:q_dobj();
    $test_utils:assert_eq(fw_q.type, 'dobj_pos_noun, "q_dobj() type");
    fw_r = this:r_dobj();
    $test_utils:assert_eq(fw_r.type, 'dobj_reflexive, "r_dobj() type");
    return true;
  endmethod

  method test_pronouns_iobj owner: HACKER
    "Test indirect object pronoun substitutions.";
    fw_s = this:s_iobj();
    $test_utils:assert_eq(fw_s.type, 'iobj_subject, "s_iobj() type");
    fw_o = this:o_iobj();
    $test_utils:assert_eq(fw_o.type, 'iobj_object, "o_iobj() type");
    fw_p = this:p_iobj();
    $test_utils:assert_eq(fw_p.type, 'iobj_pos_adj, "p_iobj() type");
    fw_q = this:q_iobj();
    $test_utils:assert_eq(fw_q.type, 'iobj_pos_noun, "q_iobj() type");
    fw_r = this:r_iobj();
    $test_utils:assert_eq(fw_r.type, 'iobj_reflexive, "r_iobj() type");
    return true;
  endmethod

  method test_verb_conjugation_be owner: HACKER
    "Test verb_be() conjugation flyweights.";
    fw_be = this:verb_be();
    $test_utils:assert_eq(fw_be.type, 'verb_be, "verb_be() type");
    fw_be_d = this:verb_be_dobj();
    $test_utils:assert_eq(fw_be_d.type, 'dobj_verb_be, "verb_be_dobj() type");
    fw_be_i = this:verb_be_iobj();
    $test_utils:assert_eq(fw_be_i.type, 'iobj_verb_be, "verb_be_iobj() type");
    return true;
  endmethod

  method test_verb_conjugation_have owner: HACKER
    "Test verb_have() conjugation flyweights.";
    fw_have = this:verb_have();
    $test_utils:assert_eq(fw_have.type, 'verb_have, "verb_have() type");
    fw_have_d = this:verb_have_dobj();
    $test_utils:assert_eq(fw_have_d.type, 'dobj_verb_have, "verb_have_dobj() type");
    fw_have_i = this:verb_have_iobj();
    $test_utils:assert_eq(fw_have_i.type, 'iobj_verb_have, "verb_have_iobj() type");
    return true;
  endmethod

  method test_verb_conjugation_look owner: HACKER
    "Test verb_look() conjugation flyweights.";
    fw_look = this:verb_look();
    $test_utils:assert_eq(fw_look.type, 'verb_look, "verb_look() type");
    fw_look_d = this:verb_look_dobj();
    $test_utils:assert_eq(fw_look_d.type, 'dobj_verb_look, "verb_look_dobj() type");
    fw_look_i = this:verb_look_iobj();
    $test_utils:assert_eq(fw_look_i.type, 'iobj_verb_look, "verb_look_iobj() type");
    return true;
  endmethod

  method test_render_actor_perspective owner: HACKER
    "Test rendering adapts actor names and self-alternation to perspective.";
    event = $event:mk_social(player, this:nc(), " ", this:self_alt("wave", "waves"), " to ", this:the('d), "."):with_dobj(this);
    actor_view = event:transform_for(player);
    observer_view = event:transform_for(#0);
    $test_utils:assert_eq(actor_view, {"You wave to the " + this.name + "."}, "actor should see second-person rendering");
    $test_utils:assert_eq(observer_view, {player:name() + " waves to the " + this.name + "."}, "observer should see third-person rendering");
    return true;
  endmethod

  method test_eval_missing_object_bindings owner: HACKER
    "Test missing direct and indirect object substitutions render placeholders.";
    event = $event:mk_test(player);
    $test_utils:assert_eq(this:s_dobj():eval_sub(event, player), "<no-dobj>", "missing dobj subject");
    $test_utils:assert_eq(this:o_iobj():eval_sub(event, player), "<no-iobj>", "missing iobj object");
    $test_utils:assert_eq(this:verb_have_dobj():eval_sub(event, player), "<no-dobj>", "missing dobj verb");
    $test_utils:assert_eq(this:verb_look_iobj():eval_sub(event, player), "<no-iobj>", "missing iobj verb");
    return true;
  endmethod

  method test_binding_eval_and_missing_binding owner: HACKER
    "Test generic binding evaluation for self, object, scalar, and missing values.";
    event = $event:mk_test(player):with_dobj(this);
    $test_utils:assert_eq(this:binding('actor):eval_sub(event, player), "you", "actor binding should render as you to actor");
    $test_utils:assert_eq(this:binding('d):eval_sub(event, player), this:name(), "object binding should render object name");
    $test_utils:assert_eq(this:binding('missing):eval_sub(event, player), "<no-binding>", "missing binding should render placeholder");
    return true;
  endmethod

  method test_article_eval_self_and_proper_noun owner: HACKER
    "Test articles suppress article text for self and proper nouns.";
    target = $test_utils:anonymous($thing);
    target.name = "test relic";
    event = $event:mk_test(player):with_dobj(target);
    $test_utils:assert_eq(this:a('d):eval_sub(event, target), "you", "self article should render as you");
    target.is_proper_noun_name = true;
    $test_utils:assert_eq(this:the('d):eval_sub(event, player), "test relic", "proper noun should suppress definite article");
    $test_utils:assert_eq(this:a('d):eval_sub(event, player), "test relic", "proper noun should suppress indefinite article");
    return true;
  endmethod

  method test_phrase_strip_period owner: HACKER
    "Test phrase() with strip_period option.";
    result = this:phrase("Hello world.", {'strip_period});
    $test_utils:assert_eq(result, "Hello world", "strip_period phrase");
    return true;
  endmethod

  method test_phrase_initial_lowercase owner: HACKER
    "Test phrase() with initial_lowercase option.";
    result = this:phrase("Hello world", {'initial_lowercase});
    $test_utils:assert_eq(result, "hello world", "initial_lowercase phrase");
    return true;
  endmethod

  method test_phrase_both_options owner: HACKER
    "Test phrase() with both strip_period and initial_lowercase.";
    result = this:phrase("Hello world.", {'strip_period, 'initial_lowercase});
    $test_utils:assert_eq(result, "hello world", "combined phrase options");
    return true;
  endmethod

  method test_phrase_no_options owner: HACKER
    "Test phrase() with no options returns unchanged text.";
    result = this:phrase("Hello world.");
    $test_utils:assert_eq(result, "Hello world.", "phrase without options");
    return true;
  endmethod

  method test_phrase_empty_string owner: HACKER
    "Test phrase() with empty string returns empty.";
    result = this:phrase("");
    $test_utils:assert_eq(result, "", "empty phrase");
    return true;
  endmethod
endobject
