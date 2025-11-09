object PLAYER
  name: "Generic Player"
  parent: EVENT_RECEIVER
  location: FIRST_ROOM
  owner: WIZ
  readable: true

  property email_address (owner: ARCH_WIZARD, flags: "") = "";
  property oauth2_identities (owner: ARCH_WIZARD, flags: "") = {};
  property password (owner: ARCH_WIZARD, flags: "");
  property profile_picture (owner: HACKER, flags: "rc") = false;
  property pronouns (owner: HACKER, flags: "rc") = <#28, .display = "they/them", .ps = "they", .po = "them", .pp = "their", .pq = "theirs", .pr = "themselves", .is_plural = true, .verb_be = "are", .verb_have = "have">;
  property wearing (owner: HACKER, flags: "rwc") = {};

  override description = "You see a player who should get around to describing themself.";
  override import_export_id = "player";

  verb make_player (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Create a player and return a setup capability for initial configuration.";
    {_, perms} = this:check_permissions('make_player);
    set_task_perms(perms);
    new_player = this:create(@args);
    setup_cap = $root:issue_capability(new_player, {'set_player_flag, 'set_owner, 'set_name_aliases, 'set_password, 'set_programmer, 'set_email_address, 'set_oauth2_identities, 'move});
    return setup_cap;
  endverb

  verb "l*ook" (any none none) owner: ARCH_WIZARD flags: "rd"
    "Look at an object. Collects the descriptive attributes and then emits them to the player.";
    if (dobjstr == "")
      target = player.location;
    else
      try
        target = $match:match_object(dobjstr, player);
      except e (ANY)
        return this:inform_current($event:mk_not_found(player, e[2]):with_audience('utility));
      endtry
    endif
    !valid(target) && return this:inform_current(this:msg_no_dobj_match());
    look_d = target:look_self();
    player:inform_current(look_d:into_event():with_audience('utility));
  endverb

  verb "i*nventory" (any none none) owner: HACKER flags: "rd"
    "Display player's inventory using list format";
    caller != player && return E_PERM;
    items = this.contents;
    !items && return this:inform_current($event:mk_inventory(player, "You are not carrying anything."):with_audience('utility));
    "Get item names";
    item_names = { item:name() for item in (items) };
    "Create and display the inventory list";
    list_obj = $format.list:mk(item_names);
    title_obj = $format.title:mk("Inventory");
    content = $format.block:mk(title_obj, list_obj);
    event = $event:mk_inventory(player, content);
    this:inform_current(event:with_audience('utility));
  endverb

  verb "who @who" (any any any) owner: ARCH_WIZARD flags: "rd"
    "Display list of connected players using table format";
    caller != player && return E_PERM;
    players = connected_players();
    !players && return this:inform_current($event:mk_not_found(this, "No players are currently connected."):with_audience('utility));
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
      table_obj = $format.table:mk(headers, rows);
      title_obj = $format.title:mk("Who's Online");
      content = $format.block:mk(title_obj, table_obj);
      event = $event:mk_who(player, content);
      this:inform_current(event:with_audience('utility));
    else
      this:inform_current($event:mk_who(this, "No connected players found."):with_audience('utility));
    endif
  endverb

  verb "msg_no_dobj_match msg_no_iobj_match" (this none this) owner: HACKER flags: "rxd"
    return $event:mk_not_found(player, "I don't see that here."):with_audience('utility);
  endverb

  verb pronouns (this none this) owner: HACKER flags: "rxd"
    "Return the pronoun set for this player (object or flyweight).";
    return this.pronouns;
  endverb

  verb "pronoun_*" (this none this) owner: HACKER flags: "rxd"
    "Get pronoun from either preset object or custom flyweight.";
    ptype = tosym(verb[9..length(verb)]);
    p = this:pronouns();
    ptype == 'subject && return p.ps;
    ptype == 'object && return p.po;
    ptype == 'possessive && args[1] == 'adj && return p.pp;
    ptype == 'possessive && args[2] == 'noun && return p.pq;
    ptype == 'reflexive && return p.pr;
    raise(E_INVARG);
  endverb

  verb "@pronouns" (any any any) owner: ARCH_WIZARD flags: "rd"
    "Set or view your pronouns.";
    "Usage: @pronouns [pronoun-set]";
    "Examples: @pronouns they/them, @pronouns she/her, @pronouns";
    caller != this && raise(E_PERM);
    set_task_perms(this);
    if (!argstr)
      "Show current pronouns and available options";
      current = $pronouns:display(this:pronouns());
      available = $pronouns:list_presets();
      title = $format.title:mk("Your Pronouns");
      lines = {"Current: " + current, "", "Available presets: " + available:join(", ")};
      content = $format.block:mk(title, @lines);
      event = $event:mk_info(this, content);
      this:inform_current(event:with_audience('utility));
      return;
    endif
    "Try to look up the pronoun set";
    pronoun_set = $pronouns:lookup(argstr:trim());
    if (typeof(pronoun_set) != FLYWEIGHT)
      event = $event:mk_error(this, "Unknown pronoun set: " + argstr, "", "Available: " + $pronouns:list_presets():join(", "));
      this:inform_current(event:with_audience('utility));
      return;
    endif
    "Set the pronouns";
    this.pronouns = pronoun_set;
    display = $pronouns:display(pronoun_set);
    event = $event:mk_info(this, "Pronouns set to: " + display);
    this:inform_current(event:with_audience('utility));
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

  verb mk_departure_event (this none this) owner: HACKER flags: "rxd"
    {from_room, ?direction = "", ?passage_desc = "", ?to_room = #-1} = args;
    typeof(direction) == STR || (direction = "");
    typeof(passage_desc) == STR || (passage_desc = "");
    passage_desc = $sub:phrase(passage_desc, {'strip_period, 'initial_lowercase});
    parts = {$sub:nc(), " ", $sub:self_alt("head", "heads")};
    if (direction)
      parts = {@parts, " ", direction};
    else
      parts = {@parts, " out"};
    endif
    if (passage_desc)
      parts = {@parts, " through ", passage_desc};
    endif
    parts = {@parts, "."};
    event = $event:mk_move(this, @parts);
    event = event:with_metadata('preferred_content_types, {'text_djot, 'text_plain});
    valid(from_room) && (event = event:with_this(from_room));
    if (valid(to_room))
      event = event:with_iobj(to_room);
    endif
    return event;
  endverb

  verb mk_arrival_event (this none this) owner: HACKER flags: "rxd"
    {to_room, ?direction = "", ?passage_desc = "", ?from_room = #-1} = args;
    typeof(direction) == STR || (direction = "");
    typeof(passage_desc) == STR || (passage_desc = "");
    passage_desc = $sub:phrase(passage_desc, {'strip_period, 'initial_lowercase});
    parts = {$sub:nc(), " ", $sub:self_alt("arrive", "arrives")};
    if (direction)
      parts = {@parts, " from the ", direction};
    endif
    if (passage_desc)
      parts = {@parts, ", emerging from ", passage_desc};
    endif
    parts = {@parts, "."};
    event = $event:mk_move(this, @parts);
    event = event:with_metadata('preferred_content_types, {'text_djot, 'text_plain});
    valid(to_room) && (event = event:with_this(to_room));
    if (valid(from_room))
      event = event:with_iobj(from_room);
    endif
    return event;
  endverb

  verb profile_picture (this none this) owner: HACKER flags: "rxd"
    return this.profile_picture;
  endverb

  verb set_profile_picture (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller == #-1 || caller == this || caller.wizard || raise(E_PERM);
    set_task_perms(this);
    {content_type, picbin} = args;
    length(picbin) > 5 * (1 << 23) && raise(E_INVARG("Profile picture too large"));
    typeof(content_type) == STR && content_type:starts_with("image/") || raise(E_TYPE);
    typeof(picbin) == BINARY || raise(E_TYPE);
    this.profile_picture = {content_type, picbin};
  endverb

  verb set_password (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Change this player's password. Permission: wizard, owner, or 'set_password capability.";
    {this, perms} = this:check_permissions('set_password);
    set_task_perms(perms);
    {new_password} = args;
    this.password = $password:mk(new_password);
  endverb

  verb set_player_flag (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Mark this object as a player. Permission: wizard or 'set_player_flag capability.";
    {flag_value} = args;
    {this, perms} = this:check_permissions('set_player_flag);
    set_task_perms(perms);
    set_player_flag(this, flag_value);
  endverb

  verb set_programmer (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Set this player's programmer flag. Permission: wizard, owner, or 'set_programmer capability.";
    {this, perms} = this:check_permissions('set_programmer);
    set_task_perms(perms);
    {flag_value} = args;
    this.programmer = flag_value;
  endverb

  verb set_email_address (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Set this player's email address. Permission: wizard, owner, or 'set_email_address capability.";
    {this, perms} = this:check_permissions('set_email_address);
    set_task_perms(perms);
    {email} = args;
    this.email_address = email;
  endverb

  verb set_oauth2_identities (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Set this player's OAuth2 identities. Permission: wizard, owner, or 'set_oauth2_identities capability.";
    {this, perms} = this:check_permissions('set_oauth2_identities);
    set_task_perms(perms);
    {identities} = args;
    this.oauth2_identities = identities;
  endverb

  verb look_self (this none this) owner: HACKER flags: "rxd"
    base_desc = this.description;
    if (!(this in connected_players()))
      description = {base_desc, " ", $sub:sc_dobj(), " ", $sub:verb_be_dobj(), " sleeping."};
    elseif ((idle = idle_seconds(this)) < 60)
      description = {base_desc, " ", $sub:sc_dobj(), " ", $sub:verb_be_dobj(), " awake and ", $sub:verb_look_dobj(), " alert."};
    else
      time = $str_proto:from_seconds(idle);
      description = {base_desc, " ", $sub:sc_dobj(), " ", $sub:verb_be_dobj(), " awake, but ", $sub:verb_have_dobj(), " been staring off into space for ", time, "."};
    endif
    return <$look, .what = this, .title = this:name(), .description = description, {@this.contents}>;
  endverb

  verb command_environment (this none this) owner: HACKER flags: "rxd"
    "Return list of objects to match commands against.";
    {command, ?options = []} = args;
    location = this.location;
    env = {this};
    "Add player's inventory.";
    for item in (this.contents)
      valid(item) && (env = {@env, item});
    endfor
    "Add worn items to environment so their verbs are directly accessible.";
    for item in (this.wearing)
      valid(item) && (env = {@env, item});
    endfor
    "Add location and its contents.";
    if (valid(location))
      env = {@env, location};
      "Let the room/location contribute additional objects (e.g., its contents, and passages).";
      if (respond_to(location, 'command_scope_for))
        ambient = `location:command_scope_for(this) ! ANY => {}';
        typeof(ambient) == LIST && (env = {@env, @ambient});
      endif
    endif
    return env;
  endverb

  verb _get_grants (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal: Get grants map for a category. ARCH_WIZARD owned to read private property.";
    caller == this || caller_perms().wizard || raise(E_PERM);
    {category} = args;
    prop_name = "grants_" + tostr(category);
    return `this.(prop_name) ! E_PROPNF => false';
  endverb

  verb find_capability_for (this none this) owner: HACKER flags: "rxd"
    "Find a capability token for target_obj in the specified category. Returns token or false.";
    caller == this || caller_perms().wizard || raise(E_PERM);
    {target_obj, category} = args;
    typeof(target_obj) == OBJ || return false;
    typeof(category) == SYM || return false;
    "Get the grants map via wizard-owned accessor";
    grants_map = this:_get_grants(category);
    typeof(grants_map) == MAP || return false;
    "Check if we have a grant for this specific object";
    if (maphaskey(grants_map, target_obj))
      return grants_map[target_obj];
    endif
    return false;
  endverb

  verb is_actor (this none this) owner: HACKER flags: "rxd"
    "Players are actors.";
    return true;
  endverb
endobject