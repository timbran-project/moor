object THING
  name: "Generic Thing"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  fertile: true
  readable: true

  verb get (this none none) owner: HACKER flags: "rxd"
    accept_to = player:acceptable(this);
    if (!accept_to)
      event = $event:mk_no_accept(player, $sub:nc(), " can't put ", $sub:d(), " in ", $sub:ic(), "."):with_dobj(this):with_iobj(player);
      player:tell(event);
      return;
    endif
    old_location = this.location;
    this:moveto(player);
    if (old_location:isa($room))
      event = $event:mk_moved(player, $sub:nc(), " picked up ", $sub:d(), "."):with_dobj(this):with_iobj(player);
      old_location:announce(event);
    endif
  endverb

  verb drop (this none none) owner: HACKER flags: "rxd"
    if (this.location != player)
      event = $event:mk_no_drop(player, "You don't have ", $sub:d(), " to drop."):with_dobj(this):with_iobj(player);
      player:tell(event);
      return;
    endif
    new_location = player.location;
    if (!new_location:acceptable(this))
      event = $event:mk_no_drop(player, "You can't drop ", $sub:d(), " here."):with_dobj(this):with_iobj(player);
      player:tell(event);
      return;
    endif
    this:moveto(new_location);
    event = $event:mk_moved(player, $sub:nc(), " dropped ", $sub:d(), "."):with_dobj(this):with_iobj(player);
    new_location:announce(event);
  endverb

  verb acceptable (this none this) owner: HACKER flags: "rxd"
    return false;
  endverb
endobject
