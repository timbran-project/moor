object CONTAINER
  name: "Generic Container"
  parent: THING
  location: PROTOTYPE_BOX
  owner: HACKER
  fertile: true
  readable: true

  override description = "Generic container prototype for objects that can hold other items.";
  override import_export_hierarchy = {"items"};
  override import_export_id = "container";

  override object_documentation = {
    "# Containers",
    "",
    "## Overview",
    "",
    "Containers are objects that can hold other items. They inherit from Thing and add the ability to put items inside and take items out. Containers support open/close functionality and rule-based access control for all operations.",
    "",
    "## Properties",
    "",
    "### take_msg and put_msg",
    "",
    "Customizable messages shown when items are taken from or put into the container.",
    "",
    "- `take_msg`: Shown when removing an item (default: \"Alice takes a sword from the chest.\")",
    "- `put_msg`: Shown when inserting an item (default: \"Alice puts a sword in the chest.\")",
    "",
    "Customize using the `@set-message` command:",
    "",
    "```",
    "@set-message chest.take_msg {nc} {retrieve|retrieves} {d} from {i}.",
    "@set-message chest.put_msg {nc} {store|stores} {d} in {i}.",
    "```",
    "",
    "Template tokens:",
    "- `{nc}` - Actor name (capitalized)",
    "- `{retrieve|retrieves}` - Self-alternation verb",
    "- `{d}` - Direct object (the item)",
    "- `{i}` - Indirect object (the container)",
    "",
    "### open property",
    "",
    "Boolean indicating whether the container is open or closed. Containers must be open to take or put items.",
    "",
    "- `open`: Current open state (default: `true`)",
    "- `open_msg`: Message shown when opening (template)",
    "- `close_msg`: Message shown when closing (template)",
    "- `already_open_msg`: Message shown when trying to open an already open container",
    "- `already_closed_msg`: Message shown when trying to close an already closed container",
    "- `not_openable_msg`: Message shown when trying to open a container with no open_rule",
    "- `not_closeable_msg`: Message shown when trying to close a container with no close_rule",
    "",
    "### locked property",
    "",
    "Boolean indicating whether the container is locked. Locked containers cannot be opened until unlocked.",
    "",
    "- `locked`: Current lock state (default: `false`)",
    "- `lock_msg`: Message shown when locking (template)",
    "- `unlock_msg`: Message shown when unlocking (template)",
    "- `not_lockable_msg`: Message shown when trying to lock a container with no lock_rule",
    "- `not_unlockable_msg`: Message shown when trying to unlock a container with no unlock_rule",
    "",
    "### Access Control Rules",
    "",
    "Rule-based access control for container operations. Rules are datalog-style expressions that determine who can perform actions.",
    "",
    "- `take_rule`: Controls who can remove items (default: `0` = public access)",
    "- `put_rule`: Controls who can insert items (default: `0` = public access)",
    "- `open_rule`: Controls who can open the container (default: `0` = public access)",
    "- `close_rule`: Controls who can close the container (default: `0` = public access)",
    "- `lock_rule`: Controls who can lock the container (default: `0` = not lockable)",
    "- `unlock_rule`: Controls who can unlock the container (default: `0` = not unlockable)",
    "- `take_denied_msg`: Message shown when take is denied (template)",
    "- `put_denied_msg`: Message shown when put is denied (template)",
    "- `open_denied_msg`: Message shown when open is denied (template)",
    "- `close_denied_msg`: Message shown when close is denied (template)",
    "- `lock_denied_msg`: Message shown when lock is denied (template)",
    "- `unlock_denied_msg`: Message shown when unlock is denied (template)",
    "",
    "Set rules using the `@set-rule` command:",
    "",
    "```",
    "@set-rule chest.take_rule This owner_is(Accessor)?",
    "@set-rule chest.open_rule Accessor is_wizard?",
    "```",
    "",
    "Clear rules to restore public access:",
    "",
    "```",
    "@clear-rule chest.take_rule",
    "```",
    "",
    "View current rules:",
    "",
    "```",
    "@show-rule chest.take_rule",
    "```",
    "",
    "**Rule Variables** (must be capitalized):",
    "- `This` - The container itself",
    "- `Accessor` - The player attempting the action",
    "- `Dobj` - The item being taken/put (for take_rule/put_rule)",
    "- `Key` - The key object being used (for lock_rule/unlock_rule)",
    "",
    "**Available Fact Predicates** (from $root):",
    "- `This owner_is(Accessor)?` - Check if accessor owns this container",
    "- `This contains(Dobj)?` - Check if container holds item",
    "- `Dobj owner_is(Accessor)?` - Check if accessor owns the item",
    "- `Dobj location_is(This)?` - Check if item is inside this container",
    "",
    "**Available Fact Predicates** (from $container):",
    "- `This is_locked?` - Check if container is locked",
    "- `This is_open?` - Check if container is open",
    "",
    "**Available Fact Predicates** (from $actor):",
    "- `Accessor is_wizard?` - Check if accessor is a wizard",
    "- `Accessor is_programmer?` - Check if accessor is a programmer",
    "- `Accessor is_builder?` - Check if accessor is a builder",
    "",
    "**Rule Operators**:",
    "- `AND` - Both conditions must be true",
    "- `OR` - Either condition must be true",
    "- `NOT` - Condition must be false (bounded negation only)",
    "",
    "## Commands",
    "",
    "### get / take / steal <item> from <container>",
    "",
    "```",
    "get sword from chest",
    "take sword from chest",
    "steal sword from chest",
    "```",
    "",
    "Removes an item from the container and adds it to inventory. The container must be open.",
    "",
    "### put <item> in <container>",
    "",
    "```",
    "put sword in chest",
    "```",
    "",
    "Places an item from inventory into the container. The container must be open.",
    "",
    "### open <container>",
    "",
    "```",
    "open chest",
    "```",
    "",
    "Opens the container. The container must not be locked. Access is controlled by `open_rule`.",
    "",
    "### close <container>",
    "",
    "```",
    "close chest",
    "```",
    "",
    "Closes the container. Access is controlled by `close_rule`.",
    "",
    "### lock <container> with <key>",
    "",
    "```",
    "lock chest with brass key",
    "```",
    "",
    "Locks the container using a key object. Access is controlled by `lock_rule`.",
    "",
    "### unlock <container> with <key>",
    "",
    "```",
    "unlock chest with brass key",
    "```",
    "",
    "Unlocks the container using a key object. Access is controlled by `unlock_rule`.",
    "",
    "## Behavior",
    "",
    "- Containers must be open to take or put items",
    "- Locked containers cannot be opened until unlocked",
    "- Containers accept items by default (override `acceptable()` to restrict)",
    "- Looking at a container shows its contents",
    "- Items can be taken from containers if the player can carry them",
    "- Items are moved into the container, not copied",
    "",
    "## Example: Creating a Lockable Treasure Chest",
    "",
    "```moo",
    "chest = create($container);",
    "chest:set_name(\"a wooden chest\");",
    "chest.description = \"An old wooden chest with brass hinges.\";",
    "@set-rule chest.lock_rule This owner_is(Accessor)?",
    "@set-rule chest.unlock_rule This owner_is(Accessor)?",
    "sword = create($thing);",
    "sword:set_name(\"a gleaming sword\");",
    "sword:moveto(chest);",
    "```",
    "",
    "Example workflow:",
    "",
    "```",
    "> close chest",
    "You close the wooden chest.",
    "> lock chest with key",
    "You lock the wooden chest with the brass key.",
    "> unlock chest with key",
    "You unlock the wooden chest with the brass key.",
    "> open chest",
    "You open the wooden chest.",
    "> get sword from chest",
    "You take the gleaming sword from the wooden chest.",
    "```"
  };

  property take_msg (owner: HACKER, flags: "rw") = {<SUB, .capitalize = true, .type = 'actor>, " ", <SUB, .for_self = "take", .for_others = "takes", .type = 'self_alt>, " ", <SUB, .capitalize = false, .type = 'dobj>, " from ", <SUB, .capitalize = false, .type = 'iobj>, "."};
  property put_msg (owner: HACKER, flags: "rw") = {<SUB, .capitalize = true, .type = 'actor>, " ", <SUB, .for_self = "put", .for_others = "puts", .type = 'self_alt>, " ", <SUB, .capitalize = false, .type = 'dobj>, " in ", <SUB, .capitalize = false, .type = 'iobj>, "."};

  property open (owner: HACKER, flags: "rw") = true;
  property open_msg (owner: HACKER, flags: "rw") = {<SUB, .capitalize = true, .type = 'actor>, " ", <SUB, .for_self = "open", .for_others = "opens", .type = 'self_alt>, " ", <SUB, .capitalize = false, .type = 'dobj>, "."};
  property close_msg (owner: HACKER, flags: "rw") = {<SUB, .capitalize = true, .type = 'actor>, " ", <SUB, .for_self = "close", .for_others = "closes", .type = 'self_alt>, " ", <SUB, .capitalize = false, .type = 'dobj>, "."};

  property locked (owner: HACKER, flags: "rw") = false;
  property lock_msg (owner: HACKER, flags: "rw") = {<SUB, .capitalize = true, .type = 'actor>, " ", <SUB, .for_self = "lock", .for_others = "locks", .type = 'self_alt>, " ", <SUB, .capitalize = false, .type = 'iobj>, " with ", <SUB, .capitalize = false, .type = 'dobj>, "."};
  property unlock_msg (owner: HACKER, flags: "rw") = {<SUB, .capitalize = true, .type = 'actor>, " ", <SUB, .for_self = "unlock", .for_others = "unlocks", .type = 'self_alt>, " ", <SUB, .capitalize = false, .type = 'iobj>, " with ", <SUB, .capitalize = false, .type = 'dobj>, "."};

  property take_rule (owner: HACKER, flags: "r") = 0;
  property put_rule (owner: HACKER, flags: "r") = 0;
  property open_rule (owner: HACKER, flags: "r") = 0;
  property close_rule (owner: HACKER, flags: "r") = 0;
  property lock_rule (owner: HACKER, flags: "r") = 0;
  property unlock_rule (owner: HACKER, flags: "r") = 0;
  property take_denied_msg (owner: HACKER, flags: "r") = {<SUB, .capitalize = true, .type = 'iobj>, " is closed."};
  property put_denied_msg (owner: HACKER, flags: "r") = {<SUB, .capitalize = true, .type = 'iobj>, " is closed."};
  property open_denied_msg (owner: HACKER, flags: "r") = {<SUB, .capitalize = true, .type = 'iobj>, " won't open."};
  property open_locked_msg (owner: HACKER, flags: "r") = {<SUB, .capitalize = true, .type = 'dobj>, " is locked."};
  property close_denied_msg (owner: HACKER, flags: "r") = {<SUB, .capitalize = true, .type = 'iobj>, " won't close."};
  property lock_denied_msg (owner: HACKER, flags: "r") = {<SUB, .capitalize = true, .type = 'iobj>, " won't lock."};
  property unlock_denied_msg (owner: HACKER, flags: "r") = {<SUB, .capitalize = true, .type = 'iobj>, " won't unlock."};
  property not_openable_msg (owner: HACKER, flags: "r") = {<SUB, .capitalize = true, .type = 'iobj>, " can't be opened."};
  property not_closeable_msg (owner: HACKER, flags: "r") = {<SUB, .capitalize = true, .type = 'iobj>, " can't be closed."};
  property not_lockable_msg (owner: HACKER, flags: "r") = {<SUB, .capitalize = true, .type = 'iobj>, " doesn't have a lock."};
  property not_unlockable_msg (owner: HACKER, flags: "r") = {<SUB, .capitalize = true, .type = 'iobj>, " doesn't have a lock."};
  property already_open_msg (owner: HACKER, flags: "r") = {<SUB, .capitalize = true, .type = 'dobj>, " is already open."};
  property already_closed_msg (owner: HACKER, flags: "r") = {<SUB, .capitalize = true, .type = 'dobj>, " is already closed."};
  property already_locked_msg (owner: HACKER, flags: "r") = {<SUB, .capitalize = true, .type = 'dobj>, " is already locked."};
  property already_unlocked_msg (owner: HACKER, flags: "r") = {<SUB, .capitalize = true, .type = 'dobj>, " is already unlocked."};

  verb acceptable (this none this) owner: HACKER flags: "rxd"
    "Containers accept items by default";
    return true;
  endverb

  verb fact_is_locked (this none this) owner: HACKER flags: "rxd"
    "Rule predicate: Is this container locked?";
    {container} = args;
    return container.locked;
  endverb

  verb can_lock (this none this) owner: HACKER flags: "rxd"
    "Check if accessor can lock this container with key. Returns {allowed, reason}.";
    {accessor, key} = args;

    "No rule = public access";
    if (this.lock_rule == 0)
      return ['allowed -> true, 'reason -> {}];
    endif

    "Evaluate lock rule";
    result = $rule_engine:evaluate(
      this.lock_rule,
      ['This -> this, 'Accessor -> accessor, 'Key -> key]
    );

    if (result['success])
      return ['allowed -> true, 'reason -> {}];
    else
      reason = this.lock_denied_msg;
      return ['allowed -> false, 'reason -> reason];
    endif
  endverb

  verb _log (this none this) owner: ARCH_WIZARD flags: "rxd"
    server_log(@args);
  endverb

  verb can_unlock (this none this) owner: HACKER flags: "rxd"
    "Check if accessor can unlock this container with key. Returns {allowed, reason}.";
    {accessor, key} = args;

    "No rule = public access";
    if (this.unlock_rule == 0)
      return ['allowed -> true, 'reason -> {}];
    endif

    "Evaluate unlock rule";
    result = $rule_engine:evaluate(
      this.unlock_rule,
      ['This -> this, 'Accessor -> accessor, 'Key -> key]
    );

    if (result['success])
      return ['allowed -> true, 'reason -> {}];
    else
      reason = this.unlock_denied_msg;
      return ['allowed -> false, 'reason -> reason];
    endif
  endverb

  verb can_take_from (this none this) owner: HACKER flags: "rxd"
    "Check if accessor can take dobj from this container. Returns {allowed, reason}.";
    {accessor, dobj} = args;

    "Check if container is open";
    if (!this.open)
      return ['allowed -> false, 'reason -> this.take_denied_msg];
    endif

    "No rule = public access";
    if (this.take_rule == 0)
      return ['allowed -> true, 'reason -> {}];
    endif

    "Evaluate take rule";
    result = $rule_engine:evaluate(
      this.take_rule,
      ['This -> this, 'Accessor -> accessor, 'Dobj -> dobj]
    );

    if (result['success])
      return ['allowed -> true, 'reason -> {}];
    else
      reason = this.take_denied_msg;
      return ['allowed -> false, 'reason -> reason];
    endif
  endverb

  verb can_put_into (this none this) owner: HACKER flags: "rxd"
    "Check if accessor can put dobj into this container. Returns {allowed, reason}.";
    {accessor, dobj} = args;

    "Check if container is open";
    if (!this.open)
      return ['allowed -> false, 'reason -> this.put_denied_msg];
    endif

    "No rule = public access";
    if (this.put_rule == 0)
      return ['allowed -> true, 'reason -> {}];
    endif

    "Evaluate put rule";
    result = $rule_engine:evaluate(
      this.put_rule,
      ['This -> this, 'Accessor -> accessor, 'Dobj -> dobj]
    );

    if (result['success])
      return ['allowed -> true, 'reason -> {}];
    else
      reason = this.put_denied_msg;
      return ['allowed -> false, 'reason -> reason];
    endif
  endverb

  verb look_self (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Custom look that shows contents with container-appropriate language";
    set_task_perms(caller_perms());
    description = this.description;

    "Check if viewer can see contents via take_rule";
    can_view = true;
    if (this.take_rule != 0)
      "Evaluate rule without dobj binding for general access check";
      result = $rule_engine:evaluate(
        this.take_rule,
        ['This -> this, 'Accessor -> player]
      );
      can_view = result['success];
    endif

    if (can_view)
      "Show contents";
      contents_list = {};
      for item in (this.contents)
        if (valid(item))
          contents_list = {@contents_list, item:display_name()};
        endif
      endfor
      if (length(contents_list))
        description = description + "  It contains " + contents_list:english_list() + ".";
      endif
    else
      "Can't see inside";
      deny_msg = this.take_denied_msg;
      rendered_msg = $sub:render(deny_msg, ['iobj -> this]);
      description = description + "  " + rendered_msg:capitalize() + ".";
    endif

    return <$look, .what = this, .title = this:name(), .description = description>;
  endverb

  verb "get take steal grab" (any from this) owner: ARCH_WIZARD flags: "rd"
    "Take an object from this container";
    set_task_perms(caller_perms());
    if (!dobjstr || dobjstr == "")
      event = $event:mk_error(player, "Take what?");
      player:inform_current(event);
      return;
    endif
    "Match the object from dobjstr - search in this container's contents";
    try
      dobj = $match:match_object(dobjstr, this);
    except e (ANY)
      event = $event:mk_error(player, $sub:i(), " doesn't have that."):with_iobj(this);
      player:inform_current(event);
      return;
    endtry
    if (!valid(dobj) || typeof(dobj) != OBJ)
      event = $event:mk_error(player, $sub:i(), " doesn't have that."):with_iobj(this);
      player:inform_current(event);
      return;
    endif
    if (dobj.location != this)
      event = $event:mk_error(player, $sub:d(), " isn't in ", $sub:i(), "."):with_dobj(dobj):with_iobj(this);
      player:inform_current(event);
      return;
    endif
    "Check access via rule";
    access_check = this:can_take_from(player, dobj);
    if (!access_check['allowed])
      event = $event:mk_error(player, @access_check['reason]):with_dobj(dobj):with_iobj(this);
      player:inform_current(event);
      return;
    endif
    "Check if player can accept the item";
    if (!player:acceptable(dobj))
      event = $event:mk_error(player, "You can't carry ", $sub:d(), "."):with_dobj(dobj);
      player:inform_current(event);
      return;
    endif
    "Try to move it";
    try
      dobj:moveto(player);
    except e (E_PERM)
      msg = length(e) > 2 ? e[2] | "You can't take that from " + this:name() + ".";
      event = $event:mk_error(player, msg):with_dobj(dobj);
      player:inform_current(event);
      return;
    endtry
    "Fire trigger for reactions";
    this:fire_trigger('on_take, ['Actor -> player, 'Item -> dobj]);
    "Announce to room";
    if (valid(player.location))
      event = $event:mk_info(player, @this.take_msg):with_dobj(dobj):with_iobj(this):with_this(player.location);
      player.location:announce(event);
    endif
  endverb

  verb put (any in this) owner: ARCH_WIZARD flags: "rd"
    "Put an object in this container";
    set_task_perms(caller_perms());
    if (!dobjstr || dobjstr == "")
      event = $event:mk_error(player, "Put what in ", $sub:i(), "?"):with_iobj(this);
      player:inform_current(event);
      return;
    endif
    "Match the object being put from player's perspective";
    try
      dobj = $match:match_object(dobjstr, player);
    except e (ANY)
      event = $event:mk_error(player, "You don't have that.");
      player:inform_current(event);
      return;
    endtry
    if (!valid(dobj) || typeof(dobj) != OBJ)
      event = $event:mk_error(player, "You don't have that.");
      player:inform_current(event);
      return;
    endif
    if (dobj.location != player)
      event = $event:mk_error(player, "You don't have ", $sub:d(), "."):with_dobj(dobj);
      player:inform_current(event);
      return;
    endif
    if (dobj == this)
      event = $event:mk_error(player, "You can't put ", $sub:d(), " inside itself."):with_dobj(dobj);
      player:inform_current(event);
      return;
    endif
    "Check access via rule";
    access_check = this:can_put_into(player, dobj);
    if (!access_check['allowed])
      event = $event:mk_error(player, @access_check['reason]):with_dobj(dobj):with_iobj(this);
      player:inform_current(event);
      return;
    endif
    "Check if this container can accept the item";
    if (!this:acceptable(dobj))
      event = $event:mk_error(player, $sub:i(), " can't hold ", $sub:d(), "."):with_dobj(dobj):with_iobj(this);
      player:inform_current(event);
      return;
    endif
    "Move the item";
    try
      dobj:moveto(this);
    except e (E_PERM)
      msg = length(e) > 2 ? e[2] | "You can't put that in " + this:name() + ".";
      event = $event:mk_error(player, msg):with_dobj(dobj);
      player:inform_current(event);
      return;
    endtry
    "Fire trigger for reactions";
    this:fire_trigger('on_put, ['Actor -> player, 'Item -> dobj]);
    "Announce to room";
    if (valid(player.location))
      event = $event:mk_info(player, @this.put_msg):with_dobj(dobj):with_iobj(this):with_this(player.location);
      player.location:announce(event);
    endif
  endverb

  verb lock (this with any) owner: ARCH_WIZARD flags: "rd"
    "Lock this container with a key";
    set_task_perms(caller_perms());
    "Check if container is lockable";
    if (this.lock_rule == 0)
      event = $event:mk_error(player, @this.not_lockable_msg):with_iobj(this);
      player:inform_current(event);
      return;
    endif
    if (!iobjstr || iobjstr == "")
      event = $event:mk_error(player, "Lock ", $sub:i(), " with what?"):with_iobj(this);
      player:inform_current(event);
      return;
    endif
    "Match the key object from player's perspective";
    key = $match:match_object(iobjstr, player);
    if (!valid(key) || typeof(key) != OBJ)
      event = $event:mk_error(player, "You don't have that.");
      player:inform_current(event);
      return;
    endif
    "Check if already locked";
    if (this.locked)
      event = $event:mk_error(player, $sub:i(), " is already locked."):with_iobj(this);
      player:inform_current(event);
      return;
    endif
    "Check access via rule";
    access_check = this:can_lock(player, key);
    if (!access_check['allowed])
      event = $event:mk_error(player, @access_check['reason]):with_dobj(key):with_iobj(this);
      player:inform_current(event);
      return;
    endif
    "Lock it";
    this.locked = true;
    "Fire trigger for reactions";
    this:fire_trigger('on_lock, ['Actor -> player, 'Key -> key]);
    "Announce to room";
    if (valid(player.location))
      event = $event:mk_info(player, @this.lock_msg):with_dobj(key):with_iobj(this):with_this(player.location);
      player.location:announce(event);
    endif
  endverb

  verb unlock (this with any) owner: ARCH_WIZARD flags: "rd"
    "Unlock this container with a key";
    set_task_perms(caller_perms());
    "Check if container is unlockable";
    if (this.unlock_rule == 0)
      event = $event:mk_error(player, @this.not_unlockable_msg):with_iobj(this);
      player:inform_current(event);
      return;
    endif
    if (!iobjstr || iobjstr == "")
      event = $event:mk_error(player, "Unlock ", $sub:i(), " with what?"):with_iobj(this);
      player:inform_current(event);
      return;
    endif
    "Match the key object from player's perspective";
    key = $match:match_object(iobjstr, player);
    if (!valid(key) || typeof(key) != OBJ)
      event = $event:mk_error(player, "You don't have that.");
      player:inform_current(event);
      return;
    endif
    "Check if already unlocked";
    if (!this.locked)
      event = $event:mk_error(player, $sub:i(), " is already unlocked."):with_iobj(this);
      player:inform_current(event);
      return;
    endif
    "Check access via rule";
    access_check = this:can_unlock(player, key);
    if (!access_check['allowed])
      event = $event:mk_error(player, @access_check['reason]):with_dobj(key):with_iobj(this);
      player:inform_current(event);
      return;
    endif
    "Unlock it";
    this.locked = false;
    "Fire trigger for reactions";
    this:fire_trigger('on_unlock, ['Actor -> player, 'Key -> key]);
    "Announce to room";
    if (valid(player.location))
      event = $event:mk_info(player, @this.unlock_msg):with_dobj(key):with_iobj(this):with_this(player.location);
      player.location:announce(event);
    endif
  endverb

  verb can_open (this none this) owner: HACKER flags: "rxd"
    "Check if accessor can open this container. Returns {allowed, reason}.";
    {accessor} = args;

    "No rule = public access";
    if (this.open_rule == 0)
      return ['allowed -> true, 'reason -> {}];
    endif

    "Evaluate open rule";
    result = $rule_engine:evaluate(
      this.open_rule,
      ['This -> this, 'Accessor -> accessor]
    );

    if (result['success])
      return ['allowed -> true, 'reason -> {}];
    else
      reason = this.open_denied_msg;
      return ['allowed -> false, 'reason -> reason];
    endif
  endverb

  verb can_close (this none this) owner: HACKER flags: "rxd"
    "Check if accessor can close this container. Returns {allowed, reason}.";
    {accessor} = args;

    "No rule = public access";
    if (this.close_rule == 0)
      return ['allowed -> true, 'reason -> {}];
    endif

    "Evaluate close rule";
    result = $rule_engine:evaluate(
      this.close_rule,
      ['This -> this, 'Accessor -> accessor]
    );

    if (result['success])
      return ['allowed -> true, 'reason -> {}];
    else
      reason = this.close_denied_msg;
      return ['allowed -> false, 'reason -> reason];
    endif
  endverb

  verb "open op*" (this none none) owner: ARCH_WIZARD flags: "rd"
    "Open this container";
    set_task_perms(caller_perms());
    "Check if already open";
    if (this.open)
      event = $event:mk_error(player, @this.already_open_msg):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    "Check if container is locked";
    if (this.locked)
      event = $event:mk_error(player, @this.open_locked_msg):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    "Check access via rule";
    access_check = this:can_open(player);
    if (!access_check['allowed])
      event = $event:mk_error(player, @access_check['reason]):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    "Open it";
    this.open = true;
    "Fire trigger for reactions";
    this:fire_trigger('on_open, ['Actor -> player]);
    "Announce to room";
    if (valid(player.location))
      event = $event:mk_info(player, @this.open_msg):with_dobj(this):with_this(player.location);
      player.location:announce(event);
    endif
  endverb

  verb "close" (this none none) owner: ARCH_WIZARD flags: "rd"
    "Close this container";
    set_task_perms(caller_perms());
    "Check if already closed";
    if (!this.open)
      event = $event:mk_error(player, @this.already_closed_msg):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    "Check access via rule";
    access_check = this:can_close(player);
    if (!access_check['allowed])
      event = $event:mk_error(player, @access_check['reason]):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    "Close it";
    this.open = false;
    "Fire trigger for reactions";
    this:fire_trigger('on_close, ['Actor -> player]);
    "Announce to room";
    if (valid(player.location))
      event = $event:mk_info(player, @this.close_msg):with_dobj(this):with_this(player.location);
      player.location:announce(event);
    endif
  endverb

  verb fact_is_open (this none this) owner: HACKER flags: "rxd"
    "Rule predicate: Is this container open?";
    return this.open;
  endverb

endobject