object ACTOR
  name: "Generic Actor"
  parent: ROOT
  location: FIRST_ROOM
  owner: WIZ
  fertile: true
  readable: true

  override description = "Generic actor prototype providing core behavior for NPCs and players including item transfer, communication, and movement.";
  override import_export_id = "actor";

  verb is_actor (this none this) owner: HACKER flags: "rxd"
    "Actors can perform actions in the world.";
    return true;
  endverb

  verb acceptable (this none this) owner: HACKER flags: "rxd"
    "Default: actors accept items.";
    return true;
  endverb

  verb put (any in this) owner: HACKER flags: "rd"
    "Reject putting things in an actor";
    event = $event:mk_error(player, $sub:tc(), " ", $sub:verb_be(), " a person, not a container."):with_this(this);
    player:inform_current(event);
  endverb

  verb "give hand" (any at this) owner: HACKER flags: "rd"
    "Give an object to this actor";
    if (!dobjstr || dobjstr == "")
      event = $event:mk_error(player, "Give what?");
      player:inform_current(event);
      return;
    endif
    "Match the object being given from player's perspective";
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
    if (this == player)
      event = $event:mk_error(player, "You already have ", $sub:d(), "."):with_dobj(dobj);
      player:inform_current(event);
      return;
    endif
    "Check if this recipient can accept the item";
    if (!this:acceptable(dobj))
      event = $event:mk_error(player, $sub:t(), " can't accept ", $sub:d(), "."):with_dobj(dobj):with_this(this);
      player:inform_current(event);
      return;
    endif
    "Move the item";
    try
      dobj:moveto(this);
    except e (E_PERM)
      msg = length(e) > 2 ? e[2] | "You don't have permission to give that away.";
      event = $event:mk_error(player, msg):with_dobj(dobj);
      player:inform_current(event);
      return;
    endtry
    "Announce to room";
    if (valid(player.location))
      event = $event:mk_info(player, $sub:nc(), " ", $sub:self_alt("give", "gives"), " ", $sub:d(), " to ", $sub:i(), "."):with_dobj(dobj):with_iobj(this):with_this(player.location);
      player.location:announce(event);
    endif
  endverb

  verb "get take steal grab" (any from this) owner: HACKER flags: "rd"
    "Take an object from this actor";
    if (!dobjstr || dobjstr == "")
      event = $event:mk_error(player, "Take what?");
      player:inform_current(event);
      return;
    endif
    "Match the object from dobjstr - search in this container's contents";
    try
      dobj = $match:match_object(dobjstr, this);
    except e (ANY)
      event = $event:mk_error(player, $sub:t(), " doesn't have that."):with_this(this);
      player:inform_current(event);
      return;
    endtry
    if (!valid(dobj) || typeof(dobj) != OBJ)
      event = $event:mk_error(player, $sub:t(), " doesn't have that."):with_this(this);
      player:inform_current(event);
      return;
    endif
    if (dobj.location != this)
      event = $event:mk_error(player, $sub:d(), " isn't with ", $sub:t(), "."):with_dobj(dobj):with_this(this);
      player:inform_current(event);
      return;
    endif
    if (this == player)
      event = $event:mk_error(player, "You already have ", $sub:d(), "."):with_dobj(dobj);
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
endobject