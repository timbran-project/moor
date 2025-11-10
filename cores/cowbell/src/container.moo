object CONTAINER
  name: "Generic Container"
  parent: THING
  location: FIRST_ROOM
  owner: HACKER
  fertile: true
  readable: true

  override description = "Generic container prototype for objects that can hold other items.";
  override import_export_id = "container";

  verb acceptable (this none this) owner: HACKER flags: "rxd"
    "Containers accept items by default";
    return true;
  endverb

  verb look_self (this none this) owner: HACKER flags: "rxd"
    "Custom look that shows contents with container-appropriate language";
    description = this.description;
    contents_list = {};
    for item in (this.contents)
      if (valid(item))
        contents_list = {@contents_list, item:display_name()};
      endif
    endfor
    if (length(contents_list))
      description = description + "  It contains " + contents_list:english_list() + ".";
    endif
    return <$look, .what = this, .title = this:name(), .description = description>;
  endverb

  verb "get take steal grab" (any from this) owner: HACKER flags: "rd"
    "Take an object from this container";
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
    "Announce to room";
    if (valid(player.location))
      event = $event:mk_info(player, $sub:nc(), " ", $sub:self_alt("take", "takes"), " ", $sub:d(), " from ", $sub:i(), "."):with_dobj(dobj):with_iobj(this):with_this(player.location);
      player.location:announce(event);
    endif
  endverb

  verb put (any in this) owner: HACKER flags: "rd"
    "Put an object in this container";
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
    "Announce to room";
    if (valid(player.location))
      event = $event:mk_info(player, $sub:nc(), " ", $sub:self_alt("put", "puts"), " ", $sub:d(), " in ", $sub:i(), "."):with_dobj(dobj):with_iobj(this):with_this(player.location);
      player.location:announce(event);
    endif
  endverb
endobject