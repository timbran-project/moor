object SUB
    name: "Event Flyweight Delegate"
    parent: ROOT
    owner: HACKER
    readable: true

    override description = "Flyweight delegate and factory for template substitution in events.";

    verb "d dc" (this none this) owner: HACKER flags: "rxd"
        capitalize = length(verb) == 2 && verb[2] == "c";
        return <this, [type -> 'dobj, capitalize -> capitalize]>;
    endverb

    verb eval_sub (this none this) owner: HACKER flags: "rxd"
        {event} = args;
        this.type == 'actor && return this:name_sub(event.actor);
        this.type == 'location && return this:name_sub(event.actor.location);
        this.type == 'this && return this:name_sub(event.this_obj);
        this.type == 'dobj && return this:name_sub(event.dobj);
        this.type == 'iobj && return this:name_sub(event.iobj);
        this.type == 'subject && return event.actor:pronoun_subject();
        this.type == 'object && return event.actor:pronoun_object();
        this.type == 'pos_adj && return event.actor:pronoun_posessive('adj);
        this.type == 'pos_noun && return event.actor:pronoun_posessive('noun);
        this.type == 'reflexive && return event.actor:pronoun_reflexive();
        this.type == 'self_alt && return event.actor == player ? this.for_self | this.for_others;
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

    verb name_sub (this none this) owner: HACKER flags: "rxd"
        {who} = args;
        who == player && return "you";
        return who:name();
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

    verb render_as (this none this) owner: HACKER flags: "rxd"
        {content_type, event} = args;
        content = this:eval_sub(event);
        return `this.capitalize ! E_PROPNF => false' ? content:capitalize() | content;
    endverb

    verb "s sc" (this none this) owner: HACKER flags: "rxd"
        capitalize = length(verb) == 2 && verb[2] == "c";
        return <this, [type -> 'subject, capitalize -> capitalize]>;
    endverb

    verb "self_alt self_altc" (this none this) owner: HACKER flags: "rxd"
        capitalize = verb[length(verb)] == "c";
        {for_self, for_alt} = args;
        return <this, [type -> 'self_alt, capitalize -> capitalize, for_self -> for_self, for_others -> for_alt]>;
    endverb

    verb "t tc" (this none this) owner: HACKER flags: "rxd"
        capitalize = length(verb) == 2 && verb[2] == "c";
        return <this, [type -> 'this, capitalize -> capitalize]>;
    endverb
endobject
