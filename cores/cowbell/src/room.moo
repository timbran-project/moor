object ROOM
  name: "Generic Room"
  parent: ROOT
  owner: HACKER
  fertile: true
  readable: true

  verb emote (any any any) owner: HACKER flags: "rx"
    event = $event:mk_emote(player, $sub:nc(), " ", argstr):with_this(player.location);
    for who in (this:contents())
      who:isa($player) && who:tell(event);
    endfor
  endverb

  verb say (any any any) owner: HACKER flags: "rx"
    event = $event:mk_say(player, $sub:nc(), " ", $sub:self_alt("say", "says"), ", \"", argstr, "\""):with_this(player.location);
    for who in (this:contents())
      who:isa($player) && who:tell(event);
    endfor
  endverb

  verb confunc (this none this) owner: HACKER flags: "rxd"
    look_d = this:look_self();
    player:tell(look_d:into_event());
  endverb

  verb acceptable (this none this) owner: HACKER flags: "rxd"
    return true;
  endverb
endobject
