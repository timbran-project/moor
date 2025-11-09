object WEARABLE
  name: "Wearable Item"
  parent: THING
  owner: HACKER
  fertile: true
  readable: true

  override description = "Generic parent for items that can be worn by players.";
  override import_export_id = "wearable";

  verb wear (this none none) owner: HACKER flags: "rd"
    "Put on this wearable item";
    if (this.location != player)
      player:inform_current($event:mk_error(player, "You don't have that."));
      return;
    endif
    if (!is_member(this, player.wearing))
      player.wearing = {@player.wearing, this};
      player:inform_current($event:mk_info(player, "You put on " + this:name() + "."));
      `this:on_wear() ! E_VERBNF';
    else
      player:inform_current($event:mk_error(player, "You're already wearing that."));
    endif
  endverb

  verb remove (this none none) owner: HACKER flags: "rd"
    "Remove this wearable item";
    if (this.location != player)
      player:inform_current($event:mk_error(player, "You don't have that."));
      return;
    endif
    if (is_member(this, player.wearing))
      player.wearing = setremove(player.wearing, this);
      player:inform_current($event:mk_info(player, "You remove " + this:name() + "."));
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
endobject