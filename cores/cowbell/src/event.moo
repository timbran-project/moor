object EVENT
    name: "Event Flyweight Delegate"
    parent: ROOT
    owner: HACKER
    readable: true

    override description = "Flyweight delegate for events that happen in the world and which become output to send to the player. Slots must include 'verb, 'actor, 'timestamp, 'dobj, 'iobj, 'this_obj. Content to display to the player is produced by iterating the contents and calling :transform_to(this, content_type) on them, appending them together, which in the end returns a string which is meant to be sent as content_type.";

    verb "mk_*" (this none this) owner: HACKER flags: "rd"
        "mk_<verb>(actor, dobj, iobj, this_obj, ... content ... )";
        action = verb[4..length(verb)];
        {actor, dir_obj, ind_obj, this_obj, @content} = args;
        return <this, [actor -> actor, verb -> action, dobj -> dir_obj, iobj -> ind_obj, timestamp -> time(), this_obj -> this_obj], {@content}>;
    endverb

    verb transform_to (this none this) owner: HACKER flags: "rd"
        "Call 'render_as(content_type, this)' on all content, and append into a final string.";
        {?content_type = "text/plain"} = args;
        if (!this:validate())
          raise(E_INVARG);
        endif
        result_str = "";
        for entry in (this)
          if (typeof(entry) == str)
            result_str = result_str + entry;
          else
            let result = entry:render_as(content_type, this);
            result_str = result_str + entry;
          endif
        endfor
        return result_str;
    endverb

    verb validate (this none this) owner: HACKER flags: "rd"
        "Validate that the event has all the correct fields. Return false if not.";
        if (typeof(this) != flyweight)
          return false;
        endif
        try
          this.verb && this.actor && this.timestamp && this.this_obj && this.dobj && this.iobj;
          return true;
        except (E_PROPNF)
          return false;
        endtry
    endverb
endobject
