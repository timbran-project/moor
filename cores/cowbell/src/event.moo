object EVENT
  name: "Event Flyweight Delegate"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for events that happen in the world and which become output to send to the player. Slots must include 'action, 'actor, 'timestamp, 'dobj, 'iobj, 'this_obj. Content to display to the player is produced by iterating the contents and calling :transform_for(this, content_type) on them, appending them together, which in the end returns a string which is meant to be sent as content_type.";
  override import_export_id = "event";

  verb "mk_*" (this none this) owner: HACKER flags: "rxd"
    "mk_<verb>(actor, ... content ... )";
    action = verb[4..length(verb)];
    {actor, @content} = args;
    return <this, [actor -> actor, actor_name -> actor.name, verb -> action, dobj -> false, iobj -> false, timestamp -> time(), this_obj -> false], {@content}>;
  endverb

  verb "with_dobj with_iobj with_this" (this none this) owner: WIZ flags: "rxd"
    {value} = args;
    wut = tosym(verb[6..length(verb)]);
    wut = wut == 'this ? 'this_obj | wut;
    self = add_slot(this, wut, value);
    "When adding attributes that have an object target, automatically add a _name for them";
    if (valid(value) && length(value.name))
      wut_name = tosym(verb[6..length(verb)] + "_name");
      self = add_slot(self, wut_name, value.name);
    endif
    return self;
  endverb

  verb transform_for (this none this) owner: HACKER flags: "rxd"
    "Call 'compose(content_type, this)' on all content, then render to final string format.";
    {render_for, ?content_type = 'text_plain} = args;
    if (!this:validate())
      raise(E_INVARG);
    endif
    composed = {};
    for entry in (this)
      if (typeof(entry) == FLYWEIGHT)
        entry = entry:compose(render_for, content_type, this);
      endif
      "If previous entry was either non-existent or a flyweight, or our result was a flyweight, we append a new element";
      "If previous entry was a string, and we're a string, we append to it.";
      if (typeof(entry) == STR && length(composed) > 0 && typeof(composed[$]) == STR)
        composed[$] = composed[$] + " " + entry;
      else
        composed = {@composed, entry};
      endif
    endfor
    return composed;
  endverb

  verb validate (this none this) owner: HACKER flags: "rxd"
    "Validate that the event has all the correct fields. Return false if not.";
    typeof(this) == FLYWEIGHT || return false;
    s = slots(this);
    required_keys = {'actor, 'actor_name, 'verb, 'dobj, 'iobj, 'timestamp, 'this_obj};
    for k in (required_keys)
      maphaskey(s, k) || return false;
    endfor
    return true;
  endverb
endobject