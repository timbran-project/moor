object EVENT
  name: "Event Flyweight Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for events that happen in the world and which become output to send to the player. Slots must include 'action, 'actor, 'timestamp, 'dobj, 'iobj, 'this_obj. Content to display to the player is produced by iterating the contents and calling :transform_for(this, content_type) on them, appending them together, which in the end returns a string which is meant to be sent as content_type.";
  override import_export_hierarchy = {"events"};
  override import_export_id = "event";

  verb "mk_*" (this none this) owner: HACKER flags: "rxd"
    "mk_<verb>(actor, ... content ... )";
    action = verb[4..length(verb)];
    {actor, @content} = args;
    normalized = this:normalize_content(@content);
    return <this, .actor = actor, .actor_name = actor.name, .verb = action, .dobj = false, .iobj = false, .timestamp = time(), .this_obj = false, .metadata = {}, normalized>;
  endverb

  verb "with_dobj with_iobj with_this" (this none this) owner: ARCH_WIZARD flags: "rxd"
    {value} = args;
    wut = tosym(verb[6..length(verb)]);
    wut = wut == 'this ? 'this_obj | wut;
    self = flyslotset(this, wut, value);
    "When adding attributes that have an object target, automatically add a _name for them";
    if (valid(value) && length(value.name))
      wut_name = tosym(verb[6..length(verb)] + "_name");
      self = flyslotset(self, wut_name, value.name);
    endif
    return self;
  endverb

  verb transform_for (this none this) owner: HACKER flags: "rxd"
    "Call 'compose(content_type, this)' on all content, then render to final string format.";
    {render_for, ?content_type = 'text_plain} = args;
    this:validate() || raise(E_INVARG);
    composed = {};
    event_contents = flycontents(this);
    for raw_entry in (event_contents)
      entry = this:wrap_content_entry(raw_entry);
      {entry_type, entry_value} = entry;
      if (entry_type == 'string)
        typeof(entry_value) == STR || raise(E_TYPE("Event string content must be a string"));
        composed = this:append_rendered(composed, entry_value);
        continue;
      endif
      if (entry_type == 'flyweight)
        typeof(entry_value) == FLYWEIGHT || raise(E_TYPE("Event flyweight content must be a flyweight"));
        rendered = entry_value:compose(render_for, content_type, this);
        composed = this:append_rendered(composed, rendered);
        continue;
      endif
      if (entry_type == 'list)
        composed = this:append_rendered(composed, entry_value);
        continue;
      endif
      raise(E_INVARG("Unknown event content entry type: " + toliteral(entry_type)));
    endfor
    return composed;
  endverb

  verb validate (this none this) owner: HACKER flags: "rxd"
    "Validate that the event has all the correct fields. Return false if not.";
    typeof(this) == FLYWEIGHT || return false;
    s = flyslots(this);
    required_keys = {'actor, 'actor_name, 'verb, 'dobj, 'iobj, 'timestamp, 'this_obj};
    for k in (required_keys)
      maphaskey(s, k) || return false;
    endfor
    event_contents = flycontents(this);
    for entry in (event_contents)
      try
        this:wrap_content_entry(entry);
      except (ANY)
        return false;
      endtry
    endfor
    return true;
  endverb

  verb normalize_content (this none this) owner: HACKER flags: "rxd"
    return {this:wrap_content_entry(e) for e in (args)};
  endverb

  verb wrap_content_entry (this none this) owner: HACKER flags: "rxd"
    entry = args[1];
    typeof(entry) == ERR && raise(E_INVARG("Event content cannot contain error values: " + toliteral(entry)));
    typeof(entry) == STR && return {'string, entry};
    typeof(entry) == FLYWEIGHT && return {'flyweight, entry};
    typeof(entry) == LIST && length(entry) == 2 && entry[1] in {'string, 'flyweight, 'list} && return entry;
    typeof(entry) == LIST && return {'list, entry};
    raise(E_TYPE("Unsupported event content entry type: " + toliteral(entry)));
  endverb

  verb append_rendered (this none this) owner: HACKER flags: "rxd"
    {acc, value} = args;
    if (typeof(value) == LIST && length(value) == 2 && value[1] in {'string, 'flyweight, 'list})
      return this:append_rendered(acc, value[2]);
    endif
    if (typeof(value) == LIST && length(value) == 3 && typeof(value[1]) == STR)
      return {@acc, value};
    endif
    if (typeof(value) == LIST)
      for element in (value)
        acc = this:append_rendered(acc, element);
      endfor
      return acc;
    endif
    if (typeof(value) == STR)
      if (length(acc) > 0 && typeof(acc[$]) == STR)
        acc[$] = acc[$] + value;
        return acc;
      endif
      return {@acc, value};
    endif
    if (typeof(value) == FLYWEIGHT)
      return {@acc, value};
    endif
    if (typeof(value) == ERR)
      raise(E_TYPE("Event content evaluated to error: " + toliteral(value)));
    endif
    raise(E_TYPE("Unsupported rendered event content: " + toliteral(value)));
  endverb

  verb with_metadata (this none this) owner: ARCH_WIZARD flags: "rxd"
    {key, value} = args;
    metadata = `this.metadata ! E_PROPNF => {}';
    updated = {};
    replaced = false;
    for pair in (metadata)
      if (pair[1] == key)
        updated = {@updated, {key, value}};
        replaced = true;
        continue;
      endif
      updated = {@updated, pair};
    endfor
    replaced || (updated = {@updated, {key, value}});
    return flyslotset(this, 'metadata, updated);
  endverb

  verb preferred_content_types (this none this) owner: HACKER flags: "rxd"
    metadata = `this.metadata ! E_PROPNF => {}';
    for pair in (metadata)
      if (pair[1] == 'preferred_content_types)
        typeof(pair[2]) == LIST || return {};
        return pair[2];
      endif
    endfor
    return {};
  endverb

  verb audience (this none this) owner: HACKER flags: "rxd"
    "Return the audience classification stored on this event.";
    metadata = `this.metadata ! E_PROPNF => {}';
    for pair in (metadata)
      if (pair[1] == 'audience)
        return pair[2];
      endif
    endfor
    return 'narrative;
  endverb

  verb with_audience (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Attach an audience classification to the event.";
    {audience} = args;
    return this:with_metadata('audience, audience);
  endverb

  verb ensure_audience (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Ensure the event has an audience classification, using the provided default if missing.";
    {audience} = args;
    metadata = `this.metadata ! E_PROPNF => {}';
    for pair in (metadata)
      if (pair[1] == 'audience)
        return this;
      endif
    endfor
    return this:with_metadata('audience, audience);
  endverb

  verb presentation_hint (this none this) owner: HACKER flags: "rxd"
    "Return the presentation hint stored on this event.";
    metadata = `this.metadata ! E_PROPNF => {}';
    for pair in (metadata)
      if (pair[1] == 'presentation_hint)
        return pair[2];
      endif
    endfor
    return false;
  endverb

  verb with_presentation_hint (this none this) owner: HACKER flags: "rxd"
    "Attach a presentation hint to the event.";
    {hint} = args;
    return this:with_metadata('presentation_hint, hint);
  endverb

  verb get_binding (this none this) owner: HACKER flags: "rxd"
    "Resolve a binding name to a value from the event context.";
    {name} = args;
    bindings = ['dobj -> this.dobj, 'd -> this.dobj, 'dc -> this.dobj, 'iobj -> this.iobj, 'i -> this.iobj, 'ic -> this.iobj, 'actor -> this.actor, 'n -> this.actor, 'nc -> this.actor, 'location -> this.actor.location, 'l -> this.actor.location, 'lc -> this.actor.location, 'this -> this.this_obj, 't -> this.this_obj, 'tc -> this.this_obj];
    return maphaskey(bindings, name) ? bindings[name] | false;
  endverb
endobject