object SUB
  name: "Substitutions Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Flyweight delegate and factory for template substitution in events.";
  override import_export_id = "sub";

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

  verb "self_alt self_altc" (this none this) owner: HACKER flags: "rxd"
    capitalize = verb[length(verb)] == "c";
    {for_self, for_alt} = args;
    return <this, [type -> 'self_alt, capitalize -> capitalize, for_self -> for_self, for_others -> for_alt]>;
  endverb

  verb eval_sub (this none this) owner: HACKER flags: "rxd"
    {event, render_for} = args;
    this.type == 'actor && return this:name_sub(event.actor, render_for);
    this.type == 'location && return this:name_sub(event.actor.location, render_for);
    this.type == 'this && return this:name_sub(event.this_obj, render_for);
    this.type == 'dobj && return this:name_sub(event.dobj, render_for);
    this.type == 'iobj && return this:name_sub(event.iobj, render_for);
    this.type == 'subject && return event.actor:pronoun_subject();
    this.type == 'object && return event.actor:pronoun_object();
    this.type == 'pos_adj && return event.actor:pronoun_possessive('adj);
    this.type == 'pos_noun && return event.actor:pronoun_possessive('noun);
    this.type == 'reflexive && return event.actor:pronoun_reflexive();
    this.type == 'dobj_subject && return valid(event.dobj) ? event.dobj:pronoun_subject() | "<no-dobj>";
    this.type == 'dobj_object && return valid(event.dobj) ? event.dobj:pronoun_object() | "<no-dobj>";
    this.type == 'dobj_pos_adj && return valid(event.dobj) ? event.dobj:pronoun_possessive('adj) | "<no-dobj>";
    this.type == 'dobj_pos_noun && return valid(event.dobj) ? event.dobj:pronoun_possessive('noun) | "<no-dobj>";
    this.type == 'dobj_reflexive && return valid(event.dobj) ? event.dobj:pronoun_reflexive() | "<no-dobj>";
    this.type == 'iobj_subject && return valid(event.iobj) ? event.iobj:pronoun_subject() | "<no-iobj>";
    this.type == 'iobj_object && return valid(event.iobj) ? event.iobj:pronoun_object() | "<no-iobj>";
    this.type == 'iobj_pos_adj && return valid(event.iobj) ? event.iobj:pronoun_possessive('adj) | "<no-iobj>";
    this.type == 'iobj_pos_noun && return valid(event.iobj) ? event.iobj:pronoun_possessive('noun) | "<no-iobj>";
    this.type == 'iobj_reflexive && return valid(event.iobj) ? event.iobj:pronoun_reflexive() | "<no-iobj>";
    this.type == 'verb_be && return event.actor:pronouns().verb_be;
    this.type == 'verb_have && return event.actor:pronouns().verb_have;
    this.type == 'verb_look && return event.actor:pronouns().is_plural ? "look" | "looks";
    this.type == 'dobj_verb_be && return valid(event.dobj) ? event.dobj:pronouns().verb_be | "<no-dobj>";
    this.type == 'dobj_verb_have && return valid(event.dobj) ? event.dobj:pronouns().verb_have | "<no-dobj>";
    this.type == 'dobj_verb_look && return valid(event.dobj) ? event.dobj:pronouns().is_plural ? "look" | "looks" | "<no-dobj>";
    this.type == 'iobj_verb_be && return valid(event.iobj) ? event.iobj:pronouns().verb_be | "<no-iobj>";
    this.type == 'iobj_verb_have && return valid(event.iobj) ? event.iobj:pronouns().verb_have | "<no-iobj>";
    this.type == 'iobj_verb_look && return valid(event.iobj) ? event.iobj:pronouns().is_plural ? "look" | "looks" | "<no-iobj>";
    this.type == 'self_alt && return event.actor == render_for ? this.for_self | this.for_others;
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
    return <this, [type -> 'dobj, capitalize -> capitalize]>;
  endverb

  verb "i* ic*" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    return <this, [type -> 'iobj, capitalize -> capitalize]>;
  endverb

  verb "l* lc*" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    return <this, [type -> 'location, capitalize -> capitalize]>;
  endverb

  verb "n* nc*" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    return <this, [type -> 'actor, capitalize -> capitalize]>;
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
    return <this, [type -> type, capitalize -> capitalize]>;
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
    return <this, [type -> type, capitalize -> capitalize]>;
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
    return <this, [type -> type, capitalize -> capitalize]>;
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
    return <this, [type -> type, capitalize -> capitalize]>;
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
    return <this, [type -> type, capitalize -> capitalize]>;
  endverb

  verb "t* tc*" (this none this) owner: HACKER flags: "rxd"
    capitalize = index(verb, "c") != 0;
    return <this, [type -> 'this, capitalize -> capitalize]>;
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
    return <this, [type -> type]>;
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
    return <this, [type -> type]>;
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
    return <this, [type -> type]>;
  endverb
endobject