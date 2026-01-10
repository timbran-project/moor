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
    return <this, .actor = actor, .actor_name = actor.name, .verb = action, .dobj = false, .iobj = false, .timestamp = time(), .this_obj = false, normalized>;
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
        typeof(entry_value) == TYPE_STR || raise(E_TYPE("Event string content must be a string"));
        composed = this:append_rendered(composed, entry_value);
        continue;
      endif
      if (entry_type == 'flyweight)
        typeof(entry_value) == TYPE_FLYWEIGHT || raise(E_TYPE("Event flyweight content must be a flyweight"));
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
    typeof(this) == TYPE_FLYWEIGHT || return false;
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
    return { this:wrap_content_entry(e) for e in (args) };
  endverb

  verb wrap_content_entry (this none this) owner: HACKER flags: "rxd"
    entry = args[1];
    typeof(entry) == TYPE_ERR && raise(E_INVARG("Event content cannot contain error values: " + toliteral(entry)));
    typeof(entry) == TYPE_STR && return {'string, entry};
    typeof(entry) == TYPE_FLYWEIGHT && return {'flyweight, entry};
    typeof(entry) == TYPE_LIST && length(entry) == 2 && entry[1] in {'string, 'flyweight, 'list} && return entry;
    typeof(entry) == TYPE_LIST && return {'list, entry};
    raise(E_TYPE("Unsupported event content entry type: " + toliteral(entry)));
  endverb

  verb append_rendered (this none this) owner: HACKER flags: "rxd"
    {acc, value} = args;
    if (typeof(value) == TYPE_LIST && length(value) == 2 && value[1] in {'string, 'flyweight, 'list})
      return this:append_rendered(acc, value[2]);
    endif
    if (typeof(value) == TYPE_LIST && length(value) == 3 && typeof(value[1]) == TYPE_STR)
      return {@acc, value};
    endif
    if (typeof(value) == TYPE_LIST)
      for element in (value)
        suspend_if_needed();
        acc = this:append_rendered(acc, element);
      endfor
      return acc;
    endif
    if (typeof(value) == TYPE_STR)
      if (length(acc) > 0 && typeof(acc[$]) == TYPE_STR)
        acc[$] = acc[$] + value;
        return acc;
      endif
      return {@acc, value};
    endif
    if (typeof(value) == TYPE_FLYWEIGHT)
      return {@acc, value};
    endif
    if (typeof(value) == TYPE_ERR)
      raise(E_TYPE("Event content evaluated to error: " + toliteral(value)));
    endif
    raise(E_TYPE("Unsupported rendered event content: " + toliteral(value)));
  endverb

  verb with_metadata (this none this) owner: ARCH_WIZARD flags: "rxd"
    {key, value} = args;
    metadata = flyslots(this);
    content = flycontents(this);
    metadata[key] = value;
    return toflyweight(this.delegate, metadata, content);
  endverb

  verb preferred_content_types (this none this) owner: HACKER flags: "rxd"
    "Return the event's preferred content types for negotiation.";
    return `this.preferred_content_types ! E_PROPNF => {}';
  endverb

  verb audience (this none this) owner: HACKER flags: "rxd"
    "Return the audience classification stored on this event.";
    return `this.audience ! E_PROPNF => 'narrative';
  endverb

  verb with_audience (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Attach an audience classification to the event.";
    {audience} = args;
    return this:with_metadata('audience, audience);
  endverb

  verb presentation_hint (this none this) owner: HACKER flags: "rxd"
    "Return the presentation hint stored on this event.";
    return `this.presentation_hint ! E_PROPNF => false';
  endverb

  verb with_presentation_hint (this none this) owner: HACKER flags: "rxd"
    "Attach a presentation hint to the event.";
    {hint} = args;
    return this:with_metadata('presentation_hint, hint);
  endverb

  verb with_group (this none this) owner: HACKER flags: "rxd"
    "Attach a group_id for client-side message bundling.";
    "Call with (prefix) for unique per-event grouping, or (prefix, target) for stable grouping.";
    {prefix, ?target = $nothing} = args;
    if (target != $nothing && typeof(target) == TYPE_OBJ && valid(target))
      "Stable ID based on valid object reference";
      group_id = tostr(prefix) + "_" + tostr(target);
    else
      "Unique ID per event";
      group_id = tostr(prefix) + "_" + uuid();
    endif
    return this:with_metadata('group_id, group_id);
  endverb

  verb with_tts (this none this) owner: HACKER flags: "rxd"
    "Attach TTS-friendly text for screen readers.";
    "Use this when the visual content has ANSI codes, brackets, or other markup.";
    {text} = args;
    return this:with_metadata('tts_text, text);
  endverb

  verb get_binding (this none this) owner: HACKER flags: "rxd"
    "Resolve a binding name to a value from the event context.";
    {name} = args;
    bindings = ['dobj -> this.dobj, 'd -> this.dobj, 'dc -> this.dobj, 'iobj -> this.iobj, 'i -> this.iobj, 'ic -> this.iobj, 'actor -> this.actor, 'n -> this.actor, 'nc -> this.actor, 'location -> this.actor.location, 'l -> this.actor.location, 'lc -> this.actor.location, 'this -> this.this_obj, 't -> this.this_obj, 'tc -> this.this_obj];
    return maphaskey(bindings, name) ? bindings[name] | false;
  endverb

  verb ensure_audience (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Ensure event has the specified audience, return event.";
    {audience} = args;
    current = `this.audience ! E_PROPNF => 0';
    if (current == audience)
      return this;
    endif
    return this:with_audience(audience);
  endverb

  verb with_rewritable (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Mark event as rewritable. Caller provides ID, optional TTL (default 60s), optional fallback.";
    {rewrite_id, ?ttl = 60, ?fallback = 0} = args;
    self = this:with_metadata('rewritable_id, rewrite_id);
    self = self:with_metadata('rewritable_owner, this.actor);
    self = self:with_metadata('rewritable_ttl, ttl);
    if (fallback)
      self = self:with_metadata('rewritable_fallback, fallback);
    endif
    return self;
  endverb
endobject