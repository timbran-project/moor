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

  verb "l look" (any none none) owner: ARCH_WIZARD flags: "rxd"
    "Look at an object. Collects the descriptive attributes and then emits them to the player.";
    "If we don't have a match, that's a 'I don't see that there...'";
    if (dobjstr == "")
      dobj = player.location;
    endif
    !valid(dobj) && return this:tell(this:msg_no_dobj_match());
    look_d = dobj:look_self();
    player:tell(look_d:into_event());
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
    {events, @rest} = args;
    contents = this:_notify_render(connections, events);
    for content in (contents)
      let {connection_obj, content_type, output} = content;
      "Send the output to the connection in its preferred content type...";
      notify(connection_obj, output, content_type);
    endfor
  endverb

  verb _transform_content (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Transform events for a specific content type - separated for testing";
    {events, content_type} = args;
    if (typeof(events) != LIST)
      events = {events};
    endif
    output = {};
    for event in (events)
      if (typeof(event) == STR)
        content = event;
      else
        content = event:transform_for(this, content_type);
      endif
      if (typeof(content) == LIST)
        output = {@output, @content};
      else
        output = {@output, content};
      endif
    endfor
    return output;
  endverb

  verb _notify_render (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(this);
    "Render the events for the player, using the connections and their content-types.";
    "Returns a list of { { connection_obj, content_type, { content-as-list } ... }";
    {connections, events} = args;
    "Connections is of form { {connection_obj, peer_addr, idle_seconds, { content_types ... }, ... }";
    results = {};
    for connection in (connections)
      let {connection_obj, peer_addr, idle_seconds, content_types} = connection;
      "For now we'll just pick the first content-type...";
      {?content_type = 'text_plain, @others} = content_types;
      "TODO: This is what we'll replace to pseudo-jtext rendering...";
      output = toliteral(events);
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
