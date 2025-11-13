object SUB
  name: "Substitutions Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Flyweight delegate and factory for template substitution in events.";
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
    "## Technical Details",
    "",
    "- All substitution verbs use wildcard matching (e.g., `\"n* nc*\"`) to handle variations",
    "- Capitalization is controlled by checking for `\"c\"` in the verb name",
    "- The flyweight's `.capitalize` property is checked during rendering",
    "- Events are composed of lists that may contain strings, flyweights, or other content",
    "- The system recurses through content, evaluating each substitution flyweight it encounters",
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
      return valid(event.dobj) ? (event.dobj == render_for ? "are" | event.dobj:pronouns().verb_be) | "<no-dobj>";
    endif
    if (this.type == 'dobj_verb_have)
      return valid(event.dobj) ? (event.dobj == render_for ? "have" | event.dobj:pronouns().verb_have) | "<no-dobj>";
    endif
    if (this.type == 'dobj_verb_look)
      return valid(event.dobj) ? (event.dobj == render_for ? "look" | (event.dobj:pronouns().is_plural ? "look" | "looks")) | "<no-dobj>";
    endif
    if (this.type == 'iobj_verb_be)
      return valid(event.iobj) ? (event.iobj == render_for ? "are" | event.iobj:pronouns().verb_be) | "<no-iobj>";
    endif
    if (this.type == 'iobj_verb_have)
      return valid(event.iobj) ? (event.iobj == render_for ? "have" | event.iobj:pronouns().verb_have) | "<no-iobj>";
    endif
    if (this.type == 'iobj_verb_look)
      return valid(event.iobj) ? (event.iobj == render_for ? "look" | (event.iobj:pronouns().is_plural ? "look" | "looks")) | "<no-iobj>";
    endif
    if (this.type == 'self_alt)
      value = event.actor == render_for ? this.for_self | this.for_others;
      "Recursively evaluate if value is a substitution flyweight";
      if (typeof(value) == FLYWEIGHT && `value.type ! E_PROPNF => false')
        return value:eval_sub(event, render_for);
      endif
      return value;
    endif
    server_log(tostr("Unknown substitution type ", toliteral(this.type), " for event ", toliteral(event)));
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

  verb "d* dc*" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    return <this, .type = 'dobj, .capitalize = capitalize>;
  endverb

  verb "i* ic*" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    return <this, .type = 'iobj, .capitalize = capitalize>;
  endverb

  verb "l* lc*" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    return <this, .type = 'location, .capitalize = capitalize>;
  endverb

  verb "n* nc*" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    return <this, .type = 'actor, .capitalize = capitalize>;
  endverb

  verb "o* oc* o*_dobj o*_iobj oc*_dobj oc*_iobj" (this none this) owner: HACKER flags: "rxd"
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

  verb "p* pc* p*_dobj p*_iobj pc*_dobj pc*_iobj" (this none this) owner: HACKER flags: "rxd"
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

  verb "q* qc* q*_dobj q*_iobj qc*_dobj qc*_iobj" (this none this) owner: HACKER flags: "rxd"
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

  verb "r* rc* r*_dobj r*_iobj rc*_dobj rc*_iobj" (this none this) owner: HACKER flags: "rxd"
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

  verb "s* sc* s*_dobj s*_iobj sc*_dobj sc*_iobj" (this none this) owner: HACKER flags: "rxd"
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

  verb "t* tc*" (this none this) owner: HACKER flags: "rxd"
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
endobject