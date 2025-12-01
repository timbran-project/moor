object CONTAINER
  name: "Generic Container"
  parent: THING
  location: PROTOTYPE_BOX
  owner: HACKER
  fertile: true
  readable: true

  property already_closed_msg (owner: HACKER, flags: "rc") = {<#19, .type = 'dobj, .capitalize = true>, " is already closed."};
  property already_locked_msg (owner: HACKER, flags: "rc") = {<#19, .type = 'dobj, .capitalize = true>, " is already locked."};
  property already_open_msg (owner: HACKER, flags: "rc") = {<#19, .type = 'dobj, .capitalize = true>, " is already open."};
  property already_unlocked_msg (owner: HACKER, flags: "rc") = {<#19, .type = 'dobj, .capitalize = true>, " is already unlocked."};
  property close_denied_msg (owner: HACKER, flags: "rc") = {<#19, .type = 'iobj, .capitalize = true>, " won't close."};
  property close_msg (owner: HACKER, flags: "rc") = {
    <#19, .type = 'actor, .capitalize = true>,
    " ",
    <#19, .type = 'self_alt, .for_self = "close", .for_others = "closes">,
    " ",
    <#19, .type = 'dobj, .capitalize = false>,
    "."
  };
  property close_rule (owner: HACKER, flags: "rc") = 0;
  property lock_denied_msg (owner: HACKER, flags: "rc") = {<#19, .type = 'iobj, .capitalize = true>, " won't lock."};
  property lock_msg (owner: HACKER, flags: "rc") = {
    <#19, .type = 'actor, .capitalize = true>,
    " ",
    <#19, .type = 'self_alt, .for_self = "lock", .for_others = "locks">,
    " ",
    <#19, .type = 'iobj, .capitalize = false>,
    " with ",
    <#19, .type = 'dobj, .capitalize = false>,
    "."
  };
  property lock_rule (owner: HACKER, flags: "rc") = 0;
  property locked (owner: HACKER, flags: "r") = false;
  property not_closeable_msg (owner: HACKER, flags: "rc") = {<#19, .type = 'iobj, .capitalize = true>, " can't be closed."};
  property not_lockable_msg (owner: HACKER, flags: "rc") = {<#19, .type = 'iobj, .capitalize = true>, " doesn't have a lock."};
  property not_openable_msg (owner: HACKER, flags: "rc") = {<#19, .type = 'iobj, .capitalize = true>, " can't be opened."};
  property not_unlockable_msg (owner: HACKER, flags: "rc") = {<#19, .type = 'iobj, .capitalize = true>, " doesn't have a lock."};
  property open (owner: HACKER, flags: "r") = true;
  property open_denied_msg (owner: HACKER, flags: "rc") = {<#19, .type = 'iobj, .capitalize = true>, " won't open."};
  property open_locked_msg (owner: HACKER, flags: "rc") = {<#19, .type = 'dobj, .capitalize = true>, " is locked."};
  property open_msg (owner: HACKER, flags: "rc") = {
    <#19, .type = 'actor, .capitalize = true>,
    " ",
    <#19, .type = 'self_alt, .for_self = "open", .for_others = "opens">,
    " ",
    <#19, .type = 'dobj, .capitalize = false>,
    "."
  };
  property open_rule (owner: HACKER, flags: "rc") = 0;
  property put_denied_msg (owner: HACKER, flags: "rc") = {<#19, .type = 'iobj, .capitalize = true>, " is closed."};
  property put_msg (owner: HACKER, flags: "rc") = {
    <#19, .type = 'actor, .capitalize = true>,
    " ",
    <#19, .type = 'self_alt, .for_self = "put", .for_others = "puts">,
    " ",
    <#19, .type = 'dobj, .capitalize = false>,
    " in ",
    <#19, .type = 'iobj, .capitalize = false>,
    "."
  };
  property put_rule (owner: HACKER, flags: "rc") = 0;
  property take_denied_msg (owner: HACKER, flags: "rc") = {<#19, .type = 'iobj, .capitalize = true>, " is closed."};
  property take_msg (owner: HACKER, flags: "rc") = {
    <#19, .type = 'actor, .capitalize = true>,
    " ",
    <#19, .type = 'self_alt, .for_self = "take", .for_others = "takes">,
    " ",
    <#19, .type = 'dobj, .capitalize = false>,
    " from ",
    <#19, .type = 'iobj, .capitalize = false>,
    "."
  };
  property take_rule (owner: HACKER, flags: "rc") = 0;
  property unlock_denied_msg (owner: HACKER, flags: "rc") = {<#19, .type = 'iobj, .capitalize = true>, " won't unlock."};
  property unlock_msg (owner: HACKER, flags: "rc") = {
    <#19, .type = 'actor, .capitalize = true>,
    " ",
    <#19, .type = 'self_alt, .for_self = "unlock", .for_others = "unlocks">,
    " ",
    <#19, .type = 'iobj, .capitalize = false>,
    " with ",
    <#19, .type = 'dobj, .capitalize = false>,
    "."
  };
  property unlock_rule (owner: HACKER, flags: "rc") = 0;

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
    result = $rule_engine:evaluate(this.lock_rule, ['This -> this, 'Accessor -> accessor, 'Key -> key]);
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
    result = $rule_engine:evaluate(this.unlock_rule, ['This -> this, 'Accessor -> accessor, 'Key -> key]);
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
    result = $rule_engine:evaluate(this.take_rule, ['This -> this, 'Accessor -> accessor, 'Dobj -> dobj]);
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
    result = $rule_engine:evaluate(this.put_rule, ['This -> this, 'Accessor -> accessor, 'Dobj -> dobj]);
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
      result = $rule_engine:evaluate(this.take_rule, ['This -> this, 'Accessor -> player]);
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
    try
      this:do_take_from(player, dobj);
    except e (E_PERM)
      msg = length(e) > 2 ? e[2] | "You can't take that from " + this:name() + ".";
      event = $event:mk_error(player, msg):with_dobj(dobj);
      player:inform_current(event);
    endtry
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
    try
      this:do_put_into(player, dobj);
    except e (E_PERM)
      msg = length(e) > 2 ? e[2] | "You can't put that in " + this:name() + ".";
      event = $event:mk_error(player, msg):with_dobj(dobj);
      player:inform_current(event);
    endtry
  endverb

  verb lock (this with any) owner: ARCH_WIZARD flags: "rd"
    "Lock this container with a key";
    set_task_perms(this.owner);
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
    this:do_lock(player, key);
  endverb

  verb unlock (this with any) owner: ARCH_WIZARD flags: "rd"
    "Unlock this container with a key";
    set_task_perms(this.owner);
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
    this:do_unlock(player, key);
  endverb

  verb can_open (this none this) owner: HACKER flags: "rxd"
    "Check if accessor can open this container. Returns {allowed, reason}.";
    {accessor} = args;
    "No rule = public access";
    if (this.open_rule == 0)
      return ['allowed -> true, 'reason -> {}];
    endif
    "Evaluate open rule";
    result = $rule_engine:evaluate(this.open_rule, ['This -> this, 'Accessor -> accessor]);
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
    result = $rule_engine:evaluate(this.close_rule, ['This -> this, 'Accessor -> accessor]);
    if (result['success])
      return ['allowed -> true, 'reason -> {}];
    else
      reason = this.close_denied_msg;
      return ['allowed -> false, 'reason -> reason];
    endif
  endverb

  verb "open op*" (this none none) owner: ARCH_WIZARD flags: "rd"
    "Open this container";
    set_task_perms(this.owner);
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
    this:do_open(player);
  endverb

  verb close (this none none) owner: ARCH_WIZARD flags: "rd"
    "Close this container";
    set_task_perms(this.owner);
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
    this:do_close(player);
  endverb

  verb fact_is_open (this none this) owner: HACKER flags: "rxd"
    "Rule predicate: Is this container open?";
    return this.open;
  endverb

  verb do_take_from (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Core: move item from container to actor's inventory.";
    "Only callable by this object itself";
    caller != this && raise(E_PERM, "do_take_from must be called by this object");
    {who, item, ?silent = false} = args;
    item:moveto(who);
    if (!silent && valid(who.location))
      event = $event:mk_info(who, @this.take_msg):with_dobj(item):with_iobj(this):with_this(who.location);
      who.location:announce(event);
    endif
    this:fire_trigger('on_take, ['Actor -> who, 'Item -> item]);
    return true;
  endverb

  verb do_put_into (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Core: move item from actor into this container.";
    "Only callable by this object itself";
    caller != this && raise(E_PERM, "do_put_into must be called by this object");
    {who, item, ?silent = false} = args;
    item:moveto(this);
    this:fire_trigger('on_put, ['Actor -> who, 'Item -> item]);
    if (!silent && valid(who.location))
      event = $event:mk_info(who, @this.put_msg):with_dobj(item):with_iobj(this):with_this(who.location);
      who.location:announce(event);
    endif
    return true;
  endverb

  verb do_open (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Core: open this container.";
    "Only callable by this object itself";
    caller != this && raise(E_PERM, "do_open must be called by this object");
    {who, ?silent = false} = args;
    this.open = true;
    this:fire_trigger('on_open, ['Actor -> who]);
    if (!silent && valid(who.location))
      event = $event:mk_info(who, @this.open_msg):with_dobj(this):with_this(who.location);
      who.location:announce(event);
    endif
    return true;
  endverb

  verb do_close (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Core: close this container.";
    "Only callable by this object itself";
    caller != this && raise(E_PERM, "do_close must be called by this object");
    {who, ?silent = false} = args;
    this.open = false;
    this:fire_trigger('on_close, ['Actor -> who]);
    if (!silent && valid(who.location))
      event = $event:mk_info(who, @this.close_msg):with_dobj(this):with_this(who.location);
      who.location:announce(event);
    endif
    return true;
  endverb

  verb do_lock (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Core: lock this container with key.";
    "Only callable by this object itself";
    caller != this && raise(E_PERM, "do_lock must be called by this object");
    {who, key, ?silent = false} = args;
    this.locked = true;
    this:fire_trigger('on_lock, ['Actor -> who, 'Key -> key]);
    if (!silent && valid(who.location))
      event = $event:mk_info(who, @this.lock_msg):with_dobj(key):with_iobj(this):with_this(who.location);
      who.location:announce(event);
    endif
    return true;
  endverb

  verb do_unlock (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Core: unlock this container with key.";
    "Only callable by this object itself";
    caller != this && raise(E_PERM, "do_unlock must be called by this object");
    {who, key, ?silent = false} = args;
    this.locked = false;
    this:fire_trigger('on_unlock, ['Actor -> who, 'Key -> key]);
    if (!silent && valid(who.location))
      event = $event:mk_info(who, @this.unlock_msg):with_dobj(key):with_iobj(this):with_this(who.location);
      who.location:announce(event);
    endif
    return true;
  endverb

  verb action_take_from (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Action handler: actor takes item from this container.";
    set_task_perms(this.owner);
    {who, context, item} = args;
    item.location != this && return false;
    !this:can_take_from(who, item)['allowed] && return false;
    !who:acceptable(item) && return false;
    return this:do_take_from(who, item);
  endverb

  verb action_put_into (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Action handler: actor puts item into this container.";
    set_task_perms(this.owner);
    {who, context, item} = args;
    item.location != who && return false;
    !this:can_put_into(who, item)['allowed] && return false;
    !this:acceptable(item) && return false;
    return this:do_put_into(who, item);
  endverb

  verb action_open (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Action handler: actor opens this container.";
    set_task_perms(this.owner);
    {who, context} = args;
    this.open && return false;
    this.locked && return false;
    !this:can_open(who)['allowed] && return false;
    return this:do_open(who);
  endverb

  verb action_close (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Action handler: actor closes this container.";
    set_task_perms(this.owner);
    {who, context} = args;
    !this.open && return false;
    !this:can_close(who)['allowed] && return false;
    return this:do_close(who);
  endverb

  verb action_lock (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Action handler: actor locks this container with key.";
    set_task_perms(this.owner);
    {who, context, key} = args;
    this.locked && return false;
    !this:can_lock(who, key)['allowed] && return false;
    return this:do_lock(who, key);
  endverb

  verb action_unlock (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Action handler: actor unlocks this container with key.";
    set_task_perms(this.owner);
    {who, context, key} = args;
    !this.locked && return false;
    !this:can_unlock(who, key)['allowed] && return false;
    return this:do_unlock(who, key);
  endverb

  verb help_topics (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return help topics for containers.";
    {for_player, ?topic = ""} = args;
    my_topics = {$help:mk("open", "Open a container", "Use 'open <container>' to open it and see its contents.", {}, 'commands, {"close", "put"}), $help:mk("close", "Close a container", "Use 'close <container>' to close it.", {"shut"}, 'commands, {"open"}), $help:mk("put", "Put something inside", "Use 'put <thing> in <container>' to place an object inside.", {"place"}, 'commands, {"get", "open"}), $help:mk("lock", "Lock a container", "Use 'lock <container> with <key>' to lock it.", {}, 'commands, {"unlock", "open"}), $help:mk("unlock", "Unlock a container", "Use 'unlock <container> with <key>' to unlock it.", {}, 'commands, {"lock", "open"})};
    topic == "" && return my_topics;
    for t in (my_topics)
      t:matches(topic) && return t;
    endfor
    return 0;
  endverb
endobject