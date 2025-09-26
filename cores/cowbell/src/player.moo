object PLAYER
  name: "Generic Player"
  parent: ROOT
  location: FIRST_ROOM
  owner: WIZ
  fertile: true
  readable: true

  property password (owner: ARCH_WIZARD, flags: "");
  property po (owner: HACKER, flags: "rc") = "it";
  property pp (owner: HACKER, flags: "rc") = "its";
  property pq (owner: HACKER, flags: "rc") = "its";
  property pr (owner: HACKER, flags: "rc") = "itself";
  property ps (owner: HACKER, flags: "rc") = "it";

  override description = "You see a player who should get around to describing themself.";

  verb "l*ook" (any none none) owner: ARCH_WIZARD flags: "rxd"
    "Look at an object. Collects the descriptive attributes and then emits them to the player.";
    "If we don't have a match, that's a 'I don't see that there...'";
    if (dobjstr == "")
      dobj = player.location;
    endif
    !valid(dobj) && return this:tell(this:msg_no_dobj_match());
    look_d = dobj:look_self();
    player:tell(look_d:into_event());
  endverb

  verb "i*nventory" (any none none) owner: HACKER flags: "rxd"
    "Display player's inventory using list format";
    caller != player && return E_PERM;
    items = this.contents;
    !items && return this:tell($event:mk_inventory(player, "You are not carrying anything."));
    "Get item names";
    item_names = {item:name() for item in (items)};
    "Create and display the inventory list";
    list_obj = $list:mk(item_names);
    title_obj = $title:mk("Inventory");
    content = $block:mk(title_obj, list_obj);
    event = $event:mk_inventory(player, content);
    this:tell(event);
  endverb

  verb "who @who" (any any any) owner: ARCH_WIZARD flags: "rxd"
    "Display list of connected players using table format";
    caller != player && return E_PERM;
    players = connected_players();
    !players && return this:tell($event:mk_not_found(this, "No players are currently connected."));
    "Build table data";
    headers = {"Name", "Idle", "Connected", "Location"};
    rows = {};
    for p in (players)
      if (typeof(idle_time = idle_seconds(p)) != ERR)
        name = p:name();
        idle_str = idle_time:format_time_seconds();
        conn_str = connected_seconds(p):format_time_seconds();
        location_name = valid(p.location) ? p.location:name() | "(nowhere)";
        rows = {@rows, {name, idle_str, conn_str, location_name}};
      endif
    endfor
    "Create and display the table";
    if (rows)
      table_obj = $table:mk(headers, rows);
      title_obj = $title:mk("Who's Online");
      content = $block:mk(title_obj, table_obj);
      event = $event:mk_who(player, content);
      this:tell(event);
    else
      this:tell($event:mk_who(this, "No connected players found."));
    endif
  endverb

  verb "msg_no_dobj_match msg_no_iobj_match" (this none this) owner: HACKER flags: "rxd"
    return $event:mk_not_found(player, "I don't see that here.");
  endverb

  verb "pronoun_*" (this none this) owner: HACKER flags: "rxd"
    ptype = tosym(verb[9..length(verb)]);
    ptype == 'subject && return this.ps;
    ptype == 'object && return this.po;
    ptype == 'posessive && args[1] == 'adj && return this.pp;
    ptype == 'posessive && args[2] == 'noun && return this.pq;
    ptype == 'reflexive && return this.pr;
    raise(E_INVARG);
  endverb

  verb tell (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Send an event through the player's connections. Each connection has a set of preferred content-types.";
    "The player is the owner of this verb, so we can use 'this' to refer to the player.";
    "This runs as wizard perms, but _notify_render runs as the player's perms.";
    "TODO: differentiate events which should only go to a *certain* connection, e.g. look, etc vs events which should go to all connections like say, emote, etc.";
    connections = connections(this);
    {event, @rest} = args;
    contents = this:_notify_render(connections, event);
    for content in (contents)
      let {connection_obj, content_type, output} = content;
      "Send the output to the connection in its preferred content type...";
      notify(connection_obj, output, false, false, content_type);
    endfor
  endverb

  verb _notify_render (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(this);
    "Render the events for the player, using the connections and their content-types.";
    "Returns a list of { { connection_obj, content_type, { content-as-list } ... }";
    {connections, event} = args;
    "Connections is of form { {connection_obj, peer_addr, idle_seconds, { content_types ... }, ... }";
    results = {};
    for connection in (connections)
      let {connection_obj, peer_addr, idle_seconds, content_types, @rest} = connection;
      "For now we'll just pick the first content-type...";
      {?content_type = 'text_plain, @others} = content_types;
      try
        transformed = event:transform_for(this, content_type);
      except e (ANY)
        transformed = "FAILED EVENT: " + toliteral(event) + "\n                                                " + toliteral(e);
      endtry
      "Iterate the transformed values and have it turn into its output form. Strings output as strings, while HTML trees are transformed, etc.";
      output = {};
      for entry in (transformed)
        if (typeof(entry) == STR)
          output = {@output, entry};
        else
          output = {@output, entry:render(content_type)};
        endif
      endfor
      if (length(output) > 0)
        results = {@results, {connection_obj, content_type, output}};
      endif
    endfor
    return results;
  endverb

  verb acceptable (this none this) owner: HACKER flags: "rxd"
    return !is_player(args[1]);
  endverb

  verb mk_emote_event (this none this) owner: HACKER flags: "rxd"
    return $event:mk_emote(this, $sub:nc(), " ", args[1]):with_this(this.location);
  endverb

  verb mk_say_event (this none this) owner: HACKER flags: "rxd"
    return $event:mk_say(this, $sub:nc(), " ", $sub:self_alt("say", "says"), ", \"", args[1], "\""):with_this(this.location);
  endverb

  verb mk_connected_event (this none this) owner: HACKER flags: "rxd"
    return $event:mk_say(this, $sub:nc(), " ", $sub:self_alt("have", "has"), " connected.");
  endverb

  verb mk_connected_event (this none this) owner: HACKER flags: "rxd"
    return $event:mk_say(this, $sub:nc(), " ", $sub:self_alt("have", "has"), " disconnected.");
  endverb
endobject