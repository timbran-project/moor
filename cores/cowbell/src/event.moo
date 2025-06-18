object EVENT
  name: "Event Flyweight Delegate"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for events that happen in the world and which become output to send to the player. Slots must include 'action, 'actor, 'timestamp, 'dobj, 'iobj, 'this_obj. Content to display to the player is produced by iterating the contents and calling :transform_for(this, content_type) on them, appending them together, which in the end returns a string which is meant to be sent as content_type.";

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

  verb transform_for (this none this) owner: HACKER flags: "rxd"
    "Call 'compose(content_type, this)' on all content, then render to final string format.";
    {render_for, ?content_type = 'text_plain} = args;
    if (!this:validate())
      raise(E_INVARG);
    endif
    "Get the appropriate content flyweight delegate";
    if (content_type == 'text_plain)
      content_flyweight = $text_plain:mk();
    elseif (content_type == 'text_html)
      content_flyweight = $text_html:mk();
    elseif (content_type == 'text_markdown || content_type == 'text_djot)
      content_flyweight = $text_markdown:mk();
    else
      content_flyweight = $text_plain:mk();
    endif
    "Compose all entries and add to content flyweight";
    for entry in (this)
      if (typeof(entry) == FLYWEIGHT)
        composed_entry = entry:compose(render_for, content_type, this);
        if (typeof(composed_entry) == FLYWEIGHT)
          "Extract elements from the composed flyweight and add them";
          for element in (composed_entry)
            content_flyweight = content_flyweight:append_element(element);
          endfor
        else
          "Composed entry is not a flyweight (e.g., SUB returns string), add directly";
          content_flyweight = content_flyweight:append_element(composed_entry);
        endif
      elseif (typeof(entry) == STR)
        content_flyweight = content_flyweight:append_element(entry);
      else
        raise(E_TYPE, "Invalid type in event content", entry);
      endif
    endfor
    "Render the final content";
    return content_flyweight:render();
  endverb

  verb validate (this none this) owner: HACKER flags: "rxd"
    "Validate that the event has all the correct fields. Return false if not.";
    if (typeof(this) != FLYWEIGHT)
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
