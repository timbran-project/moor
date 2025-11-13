object EVENT_RECEIVER
  name: "Generic Event Receiver"
  parent: ACTOR
  location: PROTOTYPE_BOX
  owner: WIZ
  fertile: true
  readable: true

  override description = "Generic event receiver prototype providing event broadcasting and connection notification capabilities.";
  override import_export_id = "event_receiver";

  verb tell (this none this) owner: HACKER flags: "rxd"
    "Broadcast an event to all connections (via player), persisting it when the audience is narrative.";
    {event, @rest} = args;
    "Events for `tell`, the content type can only ever be text/plain or text/djot";
    output = event:transform_for(this, "text/djot");
    event_slots = flyslots(event);
    this:_notify(this, output, false, false, "text/djot", event_slots);
  endverb

  verb inform_connection (this none this) owner: HACKER flags: "rxd"
    "Deliver an event to a single connection without broadcasting or event-logging it.";
    this:_can_inform() || raise(E_PERM);
    {connection_obj, event} = args;
    info = this:_connection_entry(connection_obj);
    event = event:with_audience('utility);
    contents = this:_event_render({info}, event);
    for content in (contents)
      let {conn, content_type, output} = content;
      let event_slots = flyslots(event);
      this:_notify(conn, output, false, false, content_type, event_slots);
    endfor
    return 0;
  endverb

  verb inform_current (this none this) owner: HACKER flags: "rxd"
    "Deliver an event only to the connection executing the current task.";
    this:_can_inform() || raise(E_PERM);
    {event} = args;
    event = event:with_audience('utility);
    conns = this:_connections();
    conns || return this:tell(event);
    current = conns[1][1];
    return this:inform_connection(current, event);
  endverb

  verb _can_inform (this none this) owner: HACKER flags: "rxd"
    return valid(this.location) && caller == this.location || caller == this || caller == #0 || caller.wizard || caller_perms().wizard;
  endverb

  verb _connections (this none this) owner: ARCH_WIZARD flags: "rxd"
    this:_can_inform() || raise(E_PERM);
    return connections();
  endverb

  verb _event_render (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Render an event per connection using the negotiated content types.";
    caller == this || raise(E_PERM);
    set_task_perms(this);
    {connections, event} = args;
    audience = event:audience();
    if (audience == 'narrative)
      event = event:ensure_audience('narrative);
    endif
    results = {};
    for connection in (connections)
      let {connection_obj, peer_addr, idle_seconds, content_types, @rest} = connection;
      preferred_types = event:preferred_content_types();
      if (typeof(preferred_types) != LIST)
        preferred_types = {};
      endif
      if (!preferred_types)
        preferred_types = {"text/html", "text/plain", 'text_html, 'text_plain};
      endif
      if (audience == 'narrative)
        preferred_types = {"text/djot", "text/plain", 'text_djot, 'text_plain, @preferred_types};
      endif
      content_type = 0;
      for desired in (preferred_types)
        if (desired in content_types)
          content_type = desired;
          break;
        endif
      endfor
      if (!content_type)
        content_type = length(content_types) >= 1 ? content_types[1] | 'text_plain;
      endif
      transformed = event:transform_for(this, content_type);
      "Iterate the transformed values and have it turn into its output form. Strings output as strings, while HTML trees are transformed, etc.";
      output = {};
      for entry in (transformed)
        output = this:_extend_output(output, entry, content_type);
      endfor
      if (length(output) > 0)
        results = {@results, {connection_obj, content_type, output}};
      endif
    endfor
    return results;
  endverb

  verb _extend_output (this none this) owner: HACKER flags: "rxd"
    "Flatten rendered entries into strings, recursively handling flyweights.";
    {acc, entry, content_type} = args;
    if (typeof(entry) == STR)
      return {@acc, entry};
    elseif (typeof(entry) == LIST)
      for element in (entry)
        acc = this:_extend_output(acc, element, content_type);
      endfor
      return acc;
    elseif (typeof(entry) == FLYWEIGHT)
      rendered = entry:render(content_type);
      return this:_extend_output(acc, rendered, content_type);
    elseif (typeof(entry) == ERR)
      return {@acc, toliteral(entry)};
    else
      return {@acc, tostr(entry)};
    endif
  endverb

  verb _connection_entry (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Locate the connection info tuple for the given connection object or return E_INVARG.";
    set_task_perms(this);
    {connection_obj} = args;
    for info in (connections(this))
      if (info[1] == connection_obj)
        return info;
      endif
    endfor
    raise(E_INVARG, "Connection is not attached to this player.");
  endverb

  verb _notify (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller == this || raise(E_PERM);
    notify(@args);
  endverb
endobject