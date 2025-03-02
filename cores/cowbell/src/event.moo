object EVENT
  name: "Event Flyweight Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for events that happen in the world and which become output to send to the player. Slots must include 'action, 'actor, 'timestamp, 'dobj, 'iobj, 'this_obj. Content to display to the player is produced by iterating the contents and calling :transform_to(this, content_type) on them, appending them together, which in the end returns a string which is meant to be sent as content_type.";

  verb "mk_*" (this none this) owner: HACKER flags: "rxd"
    "mk_<verb>(actor, ... content ... )";
    action = verb[4..length(verb)];
    {actor, @content} = args;
    return <this, [actor -> actor, verb -> action, dobj -> false, iobj -> false, timestamp -> time(), this_obj -> false], {@content}>;
  endverb

  verb "with_dobj with_iobj with_this" (this none this) owner: HACKER flags: "rxd"
    {value} = args;
    wut = tosym(verb[6..length(verb)]);
    wut = wut == 'this ? 'this_obj | wut;
    return add_slot(this, wut, value);
  endverb

  verb transform_to (this none this) owner: HACKER flags: "rxd"
    "Call 'render_as(content_type, this)' on all content, and append into a final string.";
    {?content_type = "text/plain"} = args;
    if (!this:validate())
      raise(E_INVARG);
    endif
    result_str = "";
    for entry in (this)
      if (typeof(entry) == str)
        result_str = result_str + entry;
      elseif (typeof(entry) == flyweight)
        let result = entry:render_as(content_type, this);
        result_str = result_str + result;
      else
        raise(E_TYPE, "Invalid type in event content", entry);
      endif
    endfor
    return result_str;
  endverb

  verb validate (this none this) owner: HACKER flags: "rxd"
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
