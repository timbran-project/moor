object PLAYER
  name: "Generic Player"
  parent: EVENT_RECEIVER
  location: FIRST_ROOM
  owner: WIZ
  fertile: true
  readable: true

  property email_address (owner: ARCH_WIZARD, flags: "") = "";
  property oauth2_identities (owner: ARCH_WIZARD, flags: "") = {};
  property password (owner: ARCH_WIZARD, flags: "");
  property profile_picture (owner: HACKER, flags: "rc") = false;
  property pronouns (owner: HACKER, flags: "rc") = PRONOUNS_THEY_THEM;

  override description = "You see a player who should get around to describing themself.";
  override import_export_id = "player";

  verb "l*ook" (any none none) owner: ARCH_WIZARD flags: "rxd"
    "Look at an object. Collects the descriptive attributes and then emits them to the player.";
    "If we don't have a match, that's a 'I don't see that there...'";
    if (dobjstr == "")
      dobj = player.location;
    endif
    !valid(dobj) && return this:inform_current(this:msg_no_dobj_match());
    look_d = dobj:look_self();
    player:inform_current(look_d:into_event():with_audience('utility));
  endverb

  verb "i*nventory" (any none none) owner: HACKER flags: "rxd"
    "Display player's inventory using list format";
    caller != player && return E_PERM;
    items = this.contents;
    !items && return this:inform_current($event:mk_inventory(player, "You are not carrying anything."):with_audience('utility));
    "Get item names";
    item_names = { item:name() for item in (items) };
    "Create and display the inventory list";
    list_obj = $list:mk(item_names);
    title_obj = $title:mk("Inventory");
    content = $block:mk(title_obj, list_obj);
    event = $event:mk_inventory(player, content);
    this:inform_current(event:with_audience('utility));
  endverb

  verb "who @who" (any any any) owner: ARCH_WIZARD flags: "rxd"
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
      table_obj = $table:mk(headers, rows);
      title_obj = $title:mk("Who's Online");
      content = $block:mk(title_obj, table_obj);
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

  verb "@pronouns" (any any any) owner: ARCH_WIZARD flags: "rxd"
    "Set or view your pronouns.";
    "Usage: @pronouns [pronoun-set]";
    "Examples: @pronouns they/them, @pronouns she/her, @pronouns";
    caller != this && raise(E_PERM);
    set_task_perms(this);
    if (!argstr)
      "Show current pronouns and available options";
      current = $pronouns:display(this:pronouns());
      available = $pronouns:list_presets();
      title = $title:mk("Your Pronouns");
      lines = {"Current: " + current, "", "Available presets: " + available:join(", ")};
      content = $block:mk(title, @lines);
      event = $event:mk_info(this, content);
      this:inform_current(event:with_audience('utility));
      return;
    endif
    "Try to look up the pronoun set";
    pronoun_set = $pronouns:lookup(argstr:trim());
    if (typeof(pronoun_set) != OBJ)
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
endobject