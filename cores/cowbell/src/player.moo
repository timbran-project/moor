object PLAYER
  name: "Generic Player"
  parent: EVENT_RECEIVER
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  property admin_features (owner: ARCH_WIZARD, flags: "") = #-1;
  property authoring_features (owner: ARCH_WIZARD, flags: "") = #-1;
  property email_address (owner: ARCH_WIZARD, flags: "") = "c";
  property features (owner: ARCH_WIZARD, flags: "rc") = {SOCIAL_FEATURES};
  property grants_area (owner: ARCH_WIZARD, flags: "") = [];
  property grants_room (owner: ARCH_WIZARD, flags: "") = [];
  property is_builder (owner: ARCH_WIZARD, flags: "") = false;
  property llm_token_budget (owner: ARCH_WIZARD, flags: "") = 20000000;
  property llm_tokens_used (owner: ARCH_WIZARD, flags: "") = 0;
  property llm_usage_log (owner: ARCH_WIZARD, flags: "") = {};
  property oauth2_identities (owner: ARCH_WIZARD, flags: "c") = {};
  property password (owner: ARCH_WIZARD, flags: "c");
  property profile_picture (owner: HACKER, flags: "rc") = false;
  property wearing (owner: HACKER, flags: "rwc") = {};

  override description = "You see a player who should get around to describing themself.";
  override import_export_id = "player";

  verb "l*ook" (any none none) owner: ARCH_WIZARD flags: "rd"
    "Look at an object or passage direction.";
    caller == this || raise(E_PERM);
    set_task_perms(this);
    if (dobjstr == "")
      target = player.location;
    else
      "Try matching as object first";
      target = E_NONE;
      try
        target = $match:match_object(dobjstr, player);
      except e (ANY)
        "Object match failed - try as passage direction";
      endtry
      "If object match failed, try passage direction";
      if (typeof(target) == ERR)
        passage_desc = this:_look_passage(dobjstr);
        if (passage_desc)
          return this:inform_current($event:mk_info(player, passage_desc):with_audience('utility):with_presentation_hint('inset));
        else
          return this:inform_current($event:mk_not_found(player, "No object or passage found matching '" + dobjstr + "'."):with_audience('utility));
        endif
      endif
    endif
    !valid(target) && return this:inform_current(this:msg_no_dobj_match());
    look_d = target:look_self();
    player:inform_current(look_d:into_event():with_audience('utility));
  endverb

  verb _look_passage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Look at a passage direction. Returns description string or false if not found.";
    caller == this || raise(E_PERM);
    set_task_perms(this);
    {direction} = args;
    current_room = this.location;
    if (!valid(current_room))
      return false;
    endif
    area = current_room.location;
    if (!valid(area))
      return false;
    endif
    passages = area:passages_from(current_room);
    if (!passages || length(passages) == 0)
      return false;
    endif
    "Search for passage matching the direction";
    for p in (passages)
      side_a_room = `p.side_a_room ! ANY => #-1';
      side_b_room = `p.side_b_room ! ANY => #-1';
      if (current_room == side_a_room)
        label = `p.side_a_label ! ANY => ""';
        aliases = `p.side_a_aliases ! ANY => {}';
        description = `p.side_a_description ! ANY => ""';
      elseif (current_room == side_b_room)
        label = `p.side_b_label ! ANY => ""';
        aliases = `p.side_b_aliases ! ANY => {}';
        description = `p.side_b_description ! ANY => ""';
      else
        continue;
      endif
      "Check if direction matches label or any alias";
      if (label == direction)
        return description ? description | "You see a passage leading " + label + ".";
      endif
      for alias in (aliases)
        if (typeof(alias) == STR && alias == direction)
          return description ? description | "You see a passage leading " + label + ".";
        endif
      endfor
    endfor
    return false;
  endverb

  verb "i*nventory" (any none none) owner: ARCH_WIZARD flags: "rd"
    "Display player's inventory using list format";
    caller == this || raise(E_PERM);
    set_task_perms(this);
    caller != player && return E_PERM;
    items = this.contents;
    !items && return this:inform_current($event:mk_inventory(player, "You are not carrying anything."):with_audience('utility));
    "Get item names";
    item_names = { item:display_name() for item in (items) };
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

  verb "msg_no_dobj_match msg_no_iobj_match" (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Utility verb to produce a not found event for presenting to the player...";
    set_task_perms(this);
    return $event:mk_not_found(player, "I don't see that here."):with_audience('utility);
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

  verb acceptable (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    return !is_player(args[1]);
  endverb

  verb profile_picture (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    return this.profile_picture;
  endverb

  verb thumbnail (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    "Return thumbnail (profile) image data for this player.";
    return this.profile_picture;
  endverb

  verb set_profile_picture (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Update the profile picture of the given player.";
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

  verb look_self (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    base_desc = this.description;
    if (!(this in connected_players()))
      description = {base_desc, " ", $sub:sc_dobj(), " ", $sub:verb_be_dobj(), " sleeping."};
    elseif ((idle = idle_seconds(this)) < 60)
      description = {base_desc, " ", $sub:sc_dobj(), " ", $sub:verb_be_dobj(), " awake and ", $sub:verb_look_dobj(), " alert."};
    else
      time = $str_proto:from_seconds(idle);
      description = {base_desc, " ", $sub:sc_dobj(), " ", $sub:verb_be_dobj(), " awake, but ", $sub:verb_have_dobj(), " been staring off into space for ", time, "."};
    endif
    "Add wearing information if they're wearing anything";
    if (this.wearing && length(this.wearing) > 0)
      wearing_names = {};
      for item in (this.wearing)
        if (valid(item))
          wearing_names = {@wearing_names, item:display_name()};
        endif
      endfor
      if (wearing_names)
        description = {@description, " ", $sub:sc_dobj(), " ", $sub:verb_be_dobj(), " wearing ", wearing_names:english_list(), "."};
      endif
    endif
    "Don't show inventory contents when looking at a player - that's private";
    return <$look, .what = this, .title = this:name(), .description = description>;
  endverb

  verb match_environment (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller != this && caller != #0 && !caller.wizard && return E_PERM;
    "Return list of objects to match against for execution in commands.";
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
      if (respond_to(location, 'match_scope_for))
        ambient = `location:match_scope_for(this) ! ANY => {}';
        typeof(ambient) == LIST && (env = {@env, @ambient});
      endif
    endif
    return env;
  endverb

  verb command_environment (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return objects whose verbs can trigger as primary / ambient commands.";
    "This is typically just the player and their location, as in the builtin-parser, but can be extended to add e.g. feature objects or ambient environmental things that require direct interaction.";
    caller != this && caller != #0 && !caller.wizard && return E_PERM;
    location = this.location;
    env = {this};
    features = this.features;
    if (typeof(features) != LIST)
      features = {};
    endif
    env = {@env, @features};
    valid(this.authoring_features) && (env = {@env, this.authoring_features});
    valid(this.admin_features) && (env = {@env, this.admin_features});
    valid(location) && (env = {@env, location});
    return env;
  endverb

  verb _get_grants (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal: Get grants map for a category. ARCH_WIZARD owned to read private property.";
    caller == this || caller_perms().wizard || raise(E_PERM);
    {category} = args;
    prop_name = "grants_" + tostr(category);
    return `this.(prop_name) ! E_PROPNF => false';
  endverb

  verb find_capability_for (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Find a capability token for target_obj in the specified category. Returns token or false.";
    caller == this || caller_perms() == this || caller_perms().wizard || raise(E_PERM);
    set_task_perms(this);
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

  verb is_wearing (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Check if player is wearing the specified item.";
    set_task_perms(caller_perms());
    {item} = args;
    wearing_list = `this.wearing ! ANY => {}';
    return typeof(wearing_list) == LIST && is_member(item, wearing_list);
  endverb

  verb confirm (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Show a confirmation prompt and return true if confirmed, false if cancelled, or string with alternative instruction.";
    "Returns: true (confirmed), false (cancelled/no), or string (alternative feedback)";
    caller == this || caller_perms().wizard || raise(E_PERM);
    {message, ?alt_label = "Or suggest an alternative:", ?alt_placeholder = "Describe your alternative approach..."} = args;
    metadata = {{"input_type", "yes_no_alternative"}, {"prompt", message}, {"alternative_label", alt_label}, {"alternative_placeholder", alt_placeholder}};
    response = this:read_with_prompt(metadata);
    set_task_perms(this);
    if (response == "yes")
      this:inform_current($event:mk_info(this, "Confirmed."):with_audience('utility):with_presentation_hint('inset));
      return true;
    elseif (response == "no")
      this:inform_current($event:mk_info(this, "Cancelled."):with_audience('utility):with_presentation_hint('inset));
      return false;
    elseif (index(response, "alternative: ") == 1)
      alt_text = response[14..$];
      this:inform_current($event:mk_info(this, "Alternative provided: " + alt_text):with_audience('utility):with_presentation_hint('inset));
      return alt_text;
    else
      "Fallback for unexpected responses";
      this:inform_current($event:mk_info(this, "Cancelled."):with_audience('utility):with_presentation_hint('inset));
      return false;
    endif
  endverb

  verb prompt (this none this) owner: HACKER flags: "rxd"
    "Show an open-ended prompt and return the user's text response.";
    "Returns: string (user's response) or false if cancelled/empty";
    "NOTE: Uses yes_no_alternative with hidden buttons to get text input until web client supports input_type: text";
    caller == this || caller_perms().wizard || raise(E_PERM);
    {question, ?placeholder = "Enter your response..."} = args;
    metadata = {{"input_type", "yes_no_alternative"}, {"prompt", question}, {"alternative_label", "Your response:"}, {"alternative_placeholder", placeholder}};
    response = this:read_with_prompt(metadata);
    set_task_perms(this);
    "If user selected yes/no, treat as cancelled";
    if (response == "yes" || response == "no")
      this:inform_current($event:mk_info(this, "Cancelled."):with_audience('utility):with_presentation_hint('inset));
      return false;
    endif
    "Extract alternative text";
    if (index(response, "alternative: ") == 1)
      text = response[13..$];
      if (!text || text == "")
        this:inform_current($event:mk_info(this, "No response provided."):with_audience('utility):with_presentation_hint('inset));
        return false;
      endif
      return text;
    endif
    "Unexpected response format";
    this:inform_current($event:mk_info(this, "Cancelled."):with_audience('utility):with_presentation_hint('inset));
    return false;
  endverb

  verb read_multiline (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Request multiline content from the player.";
    "Host (both web and telnet) is expected to handle this via metadata.";
    {?prompt = 0} = args;
    metadata = {{'input_type, "text_area"}};
    if (typeof(prompt) == STR && length(prompt))
      metadata = {@metadata, {'prompt, prompt}};
    endif
    return this:read_with_prompt(metadata);
  endverb

  verb read_with_prompt (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Helper: Call read() with metadata, displaying prompt via notify() for telnet clients.";
    "Args: metadata (list of {key, value} pairs for read())";
    "Returns: result from read()";
    {metadata} = args;
    caller_perms().wizard || caller == this || raise(E_PERM);
    typeof(metadata) == LIST || raise(E_TYPE, "Metadata must be list");
    return read(this, metadata);
  endverb

  verb put (any in this) owner: ARCH_WIZARD flags: "rd"
    "Reject putting things in a player";
    caller == this || caller_perms().wizard || raise(E_PERM);
    set_task_perms(this);
    event = $event:mk_error(player, $sub:tc(), " ", $sub:verb_be(), " a person, not a container."):with_this(this);
    player:inform_current(event);
  endverb

  verb make_player (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Create a player and return a setup capability for initial configuration.";
    {_, perms} = this:check_permissions('make_player);
    set_task_perms(perms);
    new_player = this:create(@args);
    setup_cap = $root:issue_capability(new_player, {'set_player_flag, 'set_owner, 'set_name_aliases, 'set_password, 'set_programmer, 'set_email_address, 'set_oauth2_identities, 'move});
    return setup_cap;
  endverb
endobject