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

  verb "d dc" (this none this) owner: HACKER flags: "rxd"
    capitalize = length(verb) == 2 && verb[2] == "c";
    return <this, [type -> 'dobj, capitalize -> capitalize]>;
  endverb

  verb "i ic" (this none this) owner: HACKER flags: "rxd"
    capitalize = length(verb) == 2 && verb[2] == "c";
    return <this, [type -> 'iobj, capitalize -> capitalize]>;
  endverb

  verb "l lc" (this none this) owner: HACKER flags: "rxd"
    capitalize = length(verb) == 2 && verb[2] == "c";
    return <this, [type -> 'location, capitalize -> capitalize]>;
  endverb

  verb "n nc" (this none this) owner: HACKER flags: "rxd"
    capitalize = length(verb) == 2 && verb[2] == "c";
    return <this, [type -> 'actor, capitalize -> capitalize]>;
  endverb

  verb "o oc" (this none this) owner: HACKER flags: "rxd"
    capitalize = length(verb) == 2 && verb[2] == "c";
    return <this, [type -> 'object, capitalize -> capitalize]>;
  endverb

  verb "p pc" (this none this) owner: HACKER flags: "rxd"
    capitalize = length(verb) == 2 && verb[2] == "c";
    return <this, [type -> 'pos_adj, capitalize -> capitalize]>;
  endverb

  verb "q qc" (this none this) owner: HACKER flags: "rxd"
    capitalize = length(verb) == 2 && verb[2] == "c";
    return <this, [type -> 'pos_noun, capitalize -> capitalize]>;
  endverb

  verb "r rc" (this none this) owner: HACKER flags: "rxd"
    capitalize = length(verb) == 2 && verb[2] == "c";
    return <this, [type -> 'reflexive, capitalize -> capitalize]>;
  endverb

  verb "s sc" (this none this) owner: HACKER flags: "rxd"
    capitalize = length(verb) == 2 && verb[2] == "c";
    return <this, [type -> 'subject, capitalize -> capitalize]>;
  endverb

  verb "t tc" (this none this) owner: HACKER flags: "rxd"
    capitalize = length(verb) == 2 && verb[2] == "c";
    return <this, [type -> 'this, capitalize -> capitalize]>;
  endverb
endobject
