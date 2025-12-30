object EVENT_RECEIVER
  name: "Generic Event Receiver"
  parent: ACTOR
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  fertile: true
  readable: true

  override description = "Generic event receiver prototype providing event broadcasting and connection notification capabilities.";
  override import_export_hierarchy = {"events"};
  override import_export_id = "event_receiver";

  verb tell (this none this) owner: HACKER flags: "rxd"
    "Broadcast an event to all connections for this player, with per-connection content negotiation.";
    "Persists djot version to event log for replay.";
    {event, @rest} = args;
    event_slots = flyslots(event);
    "First, log the djot version to the event log for persistence/replay";
    transformed_djot = event:transform_for(this, 'text_djot);
    output_djot = {};
    entry_num = 0;
    for entry in (transformed_djot)
      entry_num = entry_num + 1;
      if (entry_num % 50 == 0)
        suspend_if_needed();
      endif
      output_djot = this:_extend_output(output_djot, entry, 'text_djot);
    endfor
    this:_event_log(this, output_djot, 'text_djot, event_slots);
    "Now render per-connection and notify each with appropriate content type";
    conns = this:_connections();
    if (!conns)
      return;
    endif
    contents = this:_event_render(conns, event);
    entry_num = 0;
    for content in (contents)
      entry_num = entry_num + 1;
      if (entry_num % 50 == 0)
        suspend_if_needed();
      endif
      {conn, content_type, output} = content;
      this:_notify(conn, output, false, false, content_type, event_slots);
    endfor
  endverb

  verb inform_connection (this none this) owner: HACKER flags: "rxd"
    "Deliver an event to a single connection without broadcasting or event-logging it.";
    this:_can_inform() || raise(E_PERM);
    {connection_obj, event} = args;
    info = this:_connection_entry(connection_obj);
    event = event:with_audience('utility);
    contents = this:_event_render({info}, event);
    entry_num = 0;
    for content in (contents)
      entry_num = entry_num + 1;
      if (entry_num % 50 == 0)
        suspend_if_needed();
      endif
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
    "connections() returns current connection first (but all connections globally)";
    all_conns = connections();
    if (!all_conns)
      return this:tell(event);
    endif
    current = all_conns[1][1];
    "Verify this connection belongs to us by looking it up in our connections";
    info = `this:_connection_entry(current) ! E_INVARG => 0';
    if (!info)
      "Current connection is not ours, fall back to broadcast";
      return this:tell(event);
    endif
    return this:inform_connection(current, event);
  endverb

  verb _can_inform (this none this) owner: HACKER flags: "rxd"
    return valid(this.location) && caller == this.location || caller == this || caller == #0 || caller.wizard || caller_perms().wizard;
  endverb

  verb _connections (this none this) owner: ARCH_WIZARD flags: "rxd"
    this:_can_inform() || raise(E_PERM);
    set_task_perms(this);
    return connections(this);
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
      if (typeof(preferred_types) != TYPE_LIST)
        preferred_types = {};
      endif
      if (!preferred_types)
        preferred_types = {"text/html", "text/djot", "text/plain", 'text_html, 'text_djot, 'text_plain};
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
    if (typeof(entry) == TYPE_STR)
      return {@acc, entry};
    elseif (typeof(entry) == TYPE_LIST)
      for element in (entry)
        acc = this:_extend_output(acc, element, content_type);
      endfor
      return acc;
    elseif (typeof(entry) == TYPE_FLYWEIGHT)
      rendered = entry:render(content_type);
      return this:_extend_output(acc, rendered, content_type);
    elseif (typeof(entry) == TYPE_ERR)
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

  verb _present (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller == this || raise(E_PERM);
    present(@args);
  endverb

  verb _event_log (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller == this || raise(E_PERM);
    event_log(@args);
  endverb

  verb rewrite_event (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Replace a previously-sent rewritable event with new content.";
    "Args: rewrite_id, new_content, ?connection (optional - required if called from fork)";
    this:_can_inform() || raise(E_PERM);
    {rewrite_id, new_content, ?target_conn = 0} = args;
    "Build the replacement event";
    if (typeof(new_content) == TYPE_STR)
      event = $event:mk_rewrite(this, new_content);
    elseif (typeof(new_content) == TYPE_FLYWEIGHT && new_content.delegate == $event)
      event = new_content;
    else
      event = $event:mk_rewrite(this, new_content);
    endif
    "Mark it as a rewrite targeting the original";
    event = event:with_metadata('rewrite_target, rewrite_id);
    event = event:with_audience('utility);
    "Determine which connection to send to";
    if (!target_conn)
      "No connection specified - try to find current connection";
      all_conns = connections();
      if (!all_conns || length(all_conns) == 0)
        return this:tell(event);
      endif
      target_conn = all_conns[1][1];
    endif
    "Verify and send to the target connection";
    info = `this:_connection_entry(target_conn) ! E_INVARG => 0';
    if (!info)
      return this:tell(event);
    endif
    return this:inform_connection(target_conn, event);
  endverb
endobject