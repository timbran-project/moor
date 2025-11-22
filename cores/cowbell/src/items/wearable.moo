object WEARABLE
  name: "Wearable Item"
  parent: THING
  owner: HACKER
  fertile: true
  readable: true

  override description = "Generic parent for items that can be worn by players.";
  override import_export_hierarchy = {"items"};
  override import_export_id = "wearable";

  override object_documentation = {
    "# Wearable Items",
    "",
    "## Overview",
    "",
    "Wearable items are objects that players can put on and remove from their bodies. They support body area tracking to prevent wearing conflicting items in the same location (like two hats).",
    "",
    "## Properties",
    "",
    "### body_area",
    "",
    "Optional symbol indicating which part of the body this item occupies.",
    "",
    "- Default: `false` (no body area restriction)",
    "- Examples: `'head`, `'torso`, `'feet`, `'hands`, `'neck`",
    "",
    "Set with: `@set-area <item> to <area>`",
    "",
    "When set, players cannot wear another item with the same body area simultaneously.",
    "",
    "### wear_msg and remove_msg",
    "",
    "Customizable message templates using substitutions.",
    "",
    "- `wear_msg`: Shown when item is put on (default: \"Alice puts on a hat\")",
    "- `remove_msg`: Shown when item is removed (default: \"Alice removes a hat\")",
    "",
    "Customize using the `@set-message` command:",
    "",
    "```",
    "@set-message hat.wear_msg {nc} {feel|feels} a bit more stylish putting on {d}.",
    "@set-message hat.remove_msg {nc} {feel|feels} less stylish removing {d}.",
    "```",
    "",
    "Template tokens:",
    "- `{nc}` - Actor name (capitalized)",
    "- `{feel|feels}` - Self-alternation (actor sees \"feel\", others see \"feels\")",
    "- `{d}` - Direct object (the item)",
    "",
    "## Commands",
    "",
    "### wear / put on",
    "",
    "```",
    "wear <item>",
    "put on <item>",
    "```",
    "",
    "Puts the item on the player. Returns error if:",
    "- Player doesn't have the item in inventory",
    "- Item is already being worn",
    "- Another item occupies the same body area",
    "",
    "### remove",
    "",
    "```",
    "remove <item>",
    "```",
    "",
    "Removes the item from the player. Returns error if:",
    "- Player doesn't have the item in inventory",
    "- Item is not currently being worn",
    "",
    "## Verbs for Subclasses",
    "",
    "### on_wear()",
    "",
    "Called when item is successfully worn. Override in subclasses to add custom behavior.",
    "",
    "### on_remove()",
    "",
    "Called when item is successfully removed. Override in subclasses to add custom behavior.",
    "",
    "## Example: Creating a Hat",
    "",
    "```moo",
    "hat = create($wearable);",
    "hat:set_name(\"a fancy hat\");",
    "hat.body_area = 'head;",
    "hat.description = \"A stylish hat with a wide brim.\";",
    "```"
  };

  property wear_msg (owner: HACKER, flags: "rw") = {<SUB, .capitalize = true, .type = 'actor>, " ", <SUB, .for_self = "put on", .for_others = "puts on", .type = 'self_alt>, " ", <SUB, .capitalize = false, .type = 'dobj>, "."};
  property remove_msg (owner: HACKER, flags: "rw") = {<SUB, .capitalize = true, .type = 'actor>, " ", <SUB, .for_self = "remove", .for_others = "removes", .type = 'self_alt>, " ", <SUB, .capitalize = false, .type = 'dobj>, "."};
  property body_area (owner: HACKER, flags: "rw") = false;

  verb wear (this none none) owner: HACKER flags: "rd"
    "Command verb for wearing - delegates to do_wear";
    this:do_wear();
  endverb

  verb do_wear (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Implementation verb for putting on this wearable item";
    set_task_perms(caller_perms());
    if (this.location != player)
      player:inform_current($event:mk_error(player, "You don't have that."));
      return;
    endif
    if (!is_member(this, player.wearing))
      "Check for body area conflicts";
      conflict = this:conflicting_item();
      if (valid(conflict))
        conflict_name = conflict:display_name();
        this_name = this:display_name();
        msg = "You're already wearing " + conflict_name + " on that body part. Remove it first.";
        player:inform_current($event:mk_error(player, msg));
        return;
      endif
      player.wearing = {@player.wearing, this};
      "Announce to room: 'You put on X' / 'Alice puts on X'";
      event = $event:mk_info(player, @this.wear_msg):with_dobj(this):with_this(player.location);
      if (valid(player.location))
        player.location:announce(event);
      else
        player:inform_current(event);
      endif
      `this:on_wear() ! E_VERBNF';
    else
      player:inform_current($event:mk_error(player, "You're already wearing that."));
    endif
  endverb

  verb remove (this none none) owner: HACKER flags: "rd"
    "Command verb for removing - delegates to do_remove";
    this:do_remove();
  endverb

  verb do_remove (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Implementation verb for removing this wearable item";
    set_task_perms(caller_perms());
    if (this.location != player)
      player:inform_current($event:mk_error(player, "You don't have that."));
      return;
    endif
    if (is_member(this, player.wearing))
      player.wearing = setremove(player.wearing, this);
      "Announce to room: 'You remove X' / 'Alice removes X'";
      event = $event:mk_info(player, @this.remove_msg):with_dobj(this):with_this(player.location);
      if (valid(player.location))
        player.location:announce(event);
      else
        player:inform_current(event);
      endif
      `this:on_remove() ! E_VERBNF';
    else
      player:inform_current($event:mk_error(player, "You're not wearing that."));
    endif
  endverb

  verb on_wear (this none this) owner: HACKER flags: "rxd"
    "Called when item is worn - override in children";
    return;
  endverb

  verb on_remove (this none this) owner: HACKER flags: "rxd"
    "Called when item is removed - override in children";
    return;
  endverb

  verb display_name (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return display name with article for wearing context. Override for custom descriptions.";
    set_task_perms(caller_perms());
    name = this:name();
    "Check if name already has an article";
    lower_name = name:lowercase();
    if (lower_name:starts_with("the ") || lower_name:starts_with("a ") || lower_name:starts_with("an "))
      return name;
    endif
    return name:with_indefinite_article();
  endverb

  verb wearer (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return who is wearing this item, or #-1 if not worn";
    set_task_perms(caller_perms());
    if (valid(this.location) && respond_to(this.location, 'is_wearing))
      if (`this.location:is_wearing(this) ! ANY => false')
        return this.location;
      endif
    endif
    return #-1;
  endverb

  verb conflicting_item (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Find any item already worn at this item's body area. Returns the conflicting item or #-1 if none.";
    set_task_perms(caller_perms());
    area = this.body_area;
    "If no body area defined, no conflicts possible";
    if (!area || area == false)
      return #-1;
    endif
    "Search worn items for conflicting body area";
    for worn_item in (player.wearing)
      if (valid(worn_item) && worn_item != this)
        if (worn_item.body_area == area)
          return worn_item;
        endif
      endif
    endfor
    return #-1;
  endverb

  verb "@set-area" (this to any) owner: ARCH_WIZARD flags: "rd"
    "Set the body area for this wearable. Usage: @set-area <item> to <area>";
    if (caller != this.owner && !caller.wizard)
      player:inform_current($event:mk_error(player, "You can't do that."));
      return;
    endif
    set_task_perms(caller_perms());
    if (!iobjstr || iobjstr == "")
      player:inform_current($event:mk_error(player, "Set the area to what?"));
      return;
    endif
    area_name = iobjstr:trim():tosym();
    this.body_area = area_name;
    event = $event:mk_info(player, "Body area for ", $sub:d(), " set to ", tostr(area_name), "."):with_dobj(this);
    player:inform_current(event);
  endverb

  verb moveto (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Prevent movement of worn items - they must be removed first";
    set_task_perms(caller_perms());
    {destination} = args;
    "Check if currently worn";
    if (valid(this:wearer()))
      raise(E_PERM, "Cannot move a worn item. Remove it first.");
    endif
    "Delegate to parent for permission checks and actual move";
    return pass(@args);
  endverb
endobject