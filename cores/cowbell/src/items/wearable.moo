object WEARABLE
  name: "Wearable Item"
  parent: THING
  owner: HACKER
  fertile: true
  readable: true

  override description = "Generic parent for items that can be worn by players.";
  override import_export_hierarchy = {"items"};
  override import_export_id = "wearable";

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
      player.wearing = {@player.wearing, this};
      "Announce to room: 'You put on X' / 'Alice puts on X'";
      item_desc = this:display_name();
      event = $event:mk_info(player, $sub:nc(), " ", $sub:self_alt("put on", "puts on"), " ", item_desc, "."):with_this(player.location);
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
      item_desc = this:display_name();
      event = $event:mk_info(player, $sub:nc(), " ", $sub:self_alt("remove", "removes"), " ", item_desc, "."):with_this(player.location);
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