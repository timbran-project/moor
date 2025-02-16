object SUB
    name: "Event Flyweight Delegate"
    parent: ROOT
    owner: HACKER
    readable: true

    override description = "Flyweight delegate and factory for template substitution in events.";

    verb d (this none this) owner: HACKER flags: "rd"
        return <this, [type -> 'dobj]>;
    endverb

    verb eval_sub (this none this) owner: HACKER flags: "rd"
        {event} = args;
        this.type == 'actor && return event.actor:name();
        this.type == 'location && return event.actor.location:name();
        this.type == 'this && return event.this_obj:name();
        this.type == 'dobj && return event.dobj:name();
        this.type == 'iobj && return event.iobj:name();
        this.type == 'subject && return event.actor:pronoun_subject();
        this.type == 'object && return event.actor:pronoun_object();
        this.type == 'pos_adj && return event.actor:pronoun_posessive('adj);
        this.type == 'pos_noun && return event.actor:pronoun_posessive('noun);
        this.type == 'reflexive && return event.actor:pronoun_reflexive();
    endverb

    verb i (this none this) owner: HACKER flags: "rd"
        return <this, [type -> 'iobj]>;
    endverb

    verb l (this none this) owner: HACKER flags: "rd"
        return <this, [type -> 'location]>;
    endverb

    verb n (this none this) owner: HACKER flags: "rd"
        return <this, [type -> 'actor]>;
    endverb

    verb o (this none this) owner: HACKER flags: "rd"
        return <this, [type -> 'object]>;
    endverb

    verb p (this none this) owner: HACKER flags: "rd"
        return <this, [type -> 'pos_adj]>;
    endverb

    verb q (this none this) owner: HACKER flags: "rd"
        return <this, [type -> 'pos_noun]>;
    endverb

    verb r (this none this) owner: HACKER flags: "rd"
        return <this, [type -> 'reflexive]>;
    endverb

    verb render_as (this none this) owner: HACKER flags: "rd"
        {content_type, event} = args;
        content = this:eval_sub(event);
        return this.capitalize ? content:capitalize() | content;
    endverb

    verb s (this none this) owner: HACKER flags: "rd"
        return <this, [type -> 'subject]>;
    endverb

    verb t (this none this) owner: HACKER flags: "rd"
        return <this, [type -> 'this]>;
    endverb
endobject
