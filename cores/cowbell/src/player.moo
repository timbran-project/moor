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
    list_obj = $format.list:mk(item_names);
    title_obj = $format.title:mk("Inventory");
    content = $format.block:mk(title_obj, list_obj);
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
      title = $format.title:mk("Your Pronouns");
      lines = {"Current: " + current, "", "Available presets: " + available:join(", ")};
      content = $format.block:mk(title, @lines);
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

  verb command_scope_for (this none this) owner: HACKER flags: "rxd"
    "Contribute the player and their held inventory to the command scope.";
    {actor, ?context = []} = args;
    if (actor != this)
      return {this};
    endif
    entries = `pass(@args) ! E_TYPE, E_VERBNF => {this}';
    typeof(entries) == LIST || (entries = {entries});
    inventory = this.contents;
    inventory || return entries;
    for item in (inventory)
      if (!valid(item))
        continue;
      endif
      entries = {@entries, item};
    endfor
    return entries;
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
    return <$look, [what -> this, title -> this:name(), description -> description], {@this.contents}>;
  endverb

  verb command_environment (this none this) owner: HACKER flags: "rxd"
    "Assemble the environment list used for command parsing.";
    {command, ?options = []} = args;
    "Capture contextual state for downstream scope hooks.";
    context = ['actor -> this, 'command -> command, 'options -> options];
    location = this.location;
    "Gather ambient command holders from the actor and their location.";
    ambient_providers = this:_command_ambient_providers(context);
    ambient = this:_collect_command_ambient(ambient_providers, context);
    "Seed the breadth-first scope walk with the player and their location.";
    seeds = this:_command_scope_initial(context);
    seeds || (seeds = {this});
    queue = seeds;
    processed = {};
    environment = {};
    while (length(queue) > 0)
      current = queue[1];
      if (length(queue) == 1)
        queue = {};
      else
        queue = queue[2..$];
      endif
      if (typeof(current) != OBJ)
        continue;
      endif
      if (!valid(current))
        continue;
      endif
      if (current in processed)
        continue;
      endif
      processed = {@processed, current};
      "Ask each scope provider for additional entries.";
      additions = `current:command_scope_for(this, context) ! E_TYPE, E_VERBNF => {current}';
      typeof(additions) == LIST || (additions = {additions});
      for entry in (additions)
        normalized = this:_normalize_command_scope_entry(entry);
        if (!normalized)
          continue;
        endif
        if (typeof(normalized) == OBJ)
          entry_obj = normalized;
        else
          entry_obj = normalized[1];
        endif
        queue = this:_queue_scope_object(queue, processed, entry_obj);
        if (!this:_scope_entry_visible(entry_obj, normalized, context))
          continue;
        endif
        "Record every normalized entry so we can layer ordering afterwards.";
        environment = this:_merge_scope_environment(environment, normalized);
      endfor
    endwhile
    area_scope_entries = this:_collect_area_scope_entries(context);
    for entry in (area_scope_entries)
      environment = this:_merge_scope_environment(environment, entry);
    endfor
    "Recreate the classic MOO ordering: player \u2192 inventory \u2192 room \u2192 room contents.";
    actor_entry = 0;
    location_entry = 0;
    ambient_extras = {};
    for entry in (ambient)
      entry_obj = this:_entry_object(entry);
      if (entry_obj == this && !actor_entry)
        actor_entry = entry;
        continue;
      endif
      if (valid(location) && entry_obj == location && !location_entry)
        location_entry = entry;
        continue;
      endif
      ambient_extras = {@ambient_extras, entry};
    endfor
    actor_entry || (actor_entry = this);
    if (valid(location))
      location_entry || (location_entry = location);
    endif
    inventory_entries = this:_select_entries_by_location(environment, this);
    location_entries = valid(location) ? this:_select_entries_by_location(environment, location) | {};
    area_ambient_entries = this:_collect_area_ambient_entries(context);
    for entry in (area_ambient_entries)
      if (entry)
        ambient_extras = {@ambient_extras, entry};
      endif
    endfor
    final_env = {};
    final_env = this:_merge_scope_environment(final_env, actor_entry);
    for entry in (inventory_entries)
      final_env = this:_merge_scope_environment(final_env, entry);
    endfor
    "Place the room and its visible contents immediately after the actor's inventory.";
    if (valid(location))
      final_env = this:_merge_scope_environment(final_env, location_entry);
      for entry in (location_entries)
        final_env = this:_merge_scope_environment(final_env, entry);
      endfor
    endif
    "Append any extra ambient affordances after the core room structure.";
    for entry in (ambient_extras)
      final_env = this:_merge_scope_environment(final_env, entry);
    endfor
    "Finally include any remaining scoped objects (containers, fixtures, etc.).";
    for entry in (environment)
      final_env = this:_merge_scope_environment(final_env, entry);
    endfor
    final_env || return {this};
    return final_env;
  endverb

  verb _command_scope_initial (this none this) owner: HACKER flags: "rxd"
    "Return the initial seed objects for command scope gathering.";
    {context} = args;
    seeds = {this};
    location = this.location;
    valid(location) && (seeds = {@seeds, location});
    return seeds;
  endverb

  verb _normalize_command_scope_entry (this none this) owner: HACKER flags: "rxd"
    "Coerce a scope entry into either OBJ or {OBJ, aliases...}.";
    {entry} = args;
    typeof(entry) == ERR && return 0;
    typeof(entry) == OBJ && return entry;
    typeof(entry) != LIST && return 0;
    entry && typeof(entry[1]) == OBJ || return 0;
    length(entry) == 1 && return entry[1];
    return {entry[1], @entry[2..$]};
  endverb

  verb _merge_scope_environment (this none this) owner: HACKER flags: "rxd"
    "Insert or merge a scope entry into the environment list.";
    {environment, entry} = args;
    typeof(entry) == OBJ && return this:_merge_scope_entry_obj(environment, entry);
    typeof(entry) != LIST && return environment;
    entry_obj = entry[1];
    idx = this:_find_scope_entry(environment, entry_obj);
    idx || return {@environment, entry};
    current = environment[idx];
    typeof(current) == OBJ && return this:_replace_scope_entry(environment, idx, entry);
    names = entry[2..$];
    names || return environment;
    merged = this:_merge_scope_names(current[2..$], names);
    environment[idx] = {entry_obj, @merged};
    return environment;
  endverb

  verb _merge_scope_entry_obj (this none this) owner: HACKER flags: "rxd"
    "Insert an object-only entry if it is not already present.";
    {environment, entry_obj} = args;
    idx = this:_find_scope_entry(environment, entry_obj);
    idx && return environment;
    return {@environment, entry_obj};
  endverb

  verb _merge_scope_names (this none this) owner: HACKER flags: "rxd"
    "Combine alias lists without duplicates.";
    {existing, extras} = args;
    extras || return existing;
    typeof(existing) != LIST && (existing = {});
    for name in (extras)
      if (name in existing)
        continue;
      endif
      existing = {@existing, name};
    endfor
    return existing;
  endverb

  verb _find_scope_entry (this none this) owner: HACKER flags: "rxd"
    "Locate the index of an object inside the environment list.";
    {environment, entry_obj} = args;
    idx = 1;
    for entry in (environment)
      candidate = typeof(entry) == OBJ ? entry | entry[1];
      candidate == entry_obj && return idx;
      idx = idx + 1;
    endfor
    return 0;
  endverb

  verb _replace_scope_entry (this none this) owner: HACKER flags: "rxd"
    "Replace an environment entry at a specific index.";
    {environment, idx, entry} = args;
    environment[idx] = entry;
    return environment;
  endverb

  verb _queue_scope_object (this none this) owner: HACKER flags: "rxd"
    "Queue an object for later scope expansion if it has not been processed.";
    {queue, processed, entry_obj} = args;
    typeof(entry_obj) == OBJ || return queue;
    valid(entry_obj) || return queue;
    entry_obj in processed && return queue;
    for pending in (queue)
      pending == entry_obj && return queue;
    endfor
    return {@queue, entry_obj};
  endverb

  verb _scope_entry_visible (this none this) owner: HACKER flags: "rxd"
    "Ask an object whether it should be exposed in the command scope.";
    {entry_obj, entry, context} = args;
    typeof(entry_obj) == OBJ || return false;
    valid(entry_obj) || return false;
    visible = `entry_obj:command_scope_visible(this, context) ! ANY => false';
    return visible ? true | false;
  endverb

  verb _command_ambient_providers (this none this) owner: HACKER flags: "rxd"
    "Return the list of objects allowed to provide ambient verbs.";
    {context} = args;
    providers = {this};
    location = this.location;
    valid(location) && (providers = {@providers, location});
    return providers;
  endverb

  verb _collect_command_ambient (this none this) owner: HACKER flags: "rxd"
    "Gather ambient verb holders from the allowed providers.";
    {providers, context} = args;
    ambient = {};
    typeof(providers) != LIST && return ambient;
    for provider in (providers)
      if (typeof(provider) != OBJ)
        continue;
      endif
      if (!valid(provider))
        continue;
      endif
      entries = `provider:command_ambient_for(this, context) ! E_TYPE, E_VERBNF => {provider}';
      typeof(entries) == LIST || (entries = {entries});
      for entry in (entries)
        normalized = this:_normalize_command_scope_entry(entry);
        if (!normalized)
          continue;
        endif
        if (typeof(normalized) == OBJ)
          ambient_obj = normalized;
        else
          ambient_obj = normalized[1];
        endif
        if (!this:_ambient_entry_visible(ambient_obj, normalized, context))
          continue;
        endif
        ambient = this:_merge_scope_environment(ambient, normalized);
      endfor
    endfor
    return ambient;
  endverb

  verb _ambient_entry_visible (this none this) owner: HACKER flags: "rxd"
    "Check whether an ambient entry should be exposed.";
    {ambient_obj, entry, context} = args;
    typeof(ambient_obj) == OBJ || return false;
    valid(ambient_obj) || return false;
    visible = `ambient_obj:command_ambient_visible(this, context) ! ANY => false';
    return visible ? true | false;
  endverb

  verb _select_entries_by_location (this none this) owner: HACKER flags: "rxd"
    "Return entries whose underlying object is located inside the target container.";
    {entries, container} = args;
    result = {};
    typeof(entries) != LIST && return result;
    typeof(container) != OBJ && return result;
    for entry in (entries)
      entry_obj = this:_entry_object(entry);
      if (!entry_obj)
        continue;
      endif
      if (entry_obj == container)
        continue;
      endif
      if (entry_obj.location != container)
        continue;
      endif
      result = {@result, entry};
    endfor
    return result;
  endverb

  verb _entry_object (this none this) owner: HACKER flags: "rxd"
    "Extract the object referred to by a scope entry.";
    {entry} = args;
    if (typeof(entry) == OBJ)
      return entry;
    endif
    if (typeof(entry) == LIST && entry && typeof(entry[1]) == OBJ)
      return entry[1];
    endif
    return 0;
  endverb

  verb _passage_areas (this none this) owner: HACKER flags: "rxd"
    areas = {};
    area = this.location;
    if (valid(area))
      areas = {area};
    endif
    return areas;
  endverb

  verb _collect_area_scope_entries (this none this) owner: HACKER flags: "rxd"
    {context} = args;
    room = this.location;
    valid(room) || return {};
    entries = {};
    for area in (this:_passage_areas())
      if (!valid(area))
        continue;
      endif
      area_entries = `area:scope_entries_for(room) ! E_TYPE, E_VERBNF => {}';
      if (typeof(area_entries) != LIST)
        continue;
      endif
      for entry in (area_entries)
        if (entry)
          entries = {@entries, entry};
        endif
      endfor
    endfor
    return entries;
  endverb

  verb _collect_area_ambient_entries (this none this) owner: HACKER flags: "rxd"
    {context} = args;
    room = this.location;
    valid(room) || return {};
    entries = {};
    for area in (this:_passage_areas())
      if (!valid(area))
        continue;
      endif
      area_entries = `area:ambient_entries_for(room) ! E_TYPE, E_VERBNF => {}';
      if (typeof(area_entries) != LIST)
        continue;
      endif
      for entry in (area_entries)
        if (entry)
          entries = {@entries, entry};
        endif
      endfor
    endfor
    return entries;
  endverb

  verb handle_passage_command (this none this) owner: HACKER flags: "rxd"
    {parsed} = args;
    for area in (this:_passage_areas())
      if (!valid(area))
        continue;
      endif
      handled = `area:handle_passage_command(this, parsed) ! E_TYPE, E_VERBNF => false';
      if (handled)
        return true;
      endif
    endfor
    return false;
  endverb
endobject