object ROOM
  name: "Generic Room"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  fertile: true
  readable: true

  verb emote (any any any) owner: HACKER flags: "rxd"
    this:announce(player:mk_emote_event(argstr));
  endverb

  verb say (any any any) owner: HACKER flags: "rxd"
    this:announce(player:mk_say_event(argstr));
  endverb

  verb confunc (this none this) owner: HACKER flags: "rxd"
    discon_event = player:mk_connected_event();
    this:announce(discon_event);
    look_d = this:look_self();
    player:tell(look_d:into_event());
  endverb

  verb acceptable (this none this) owner: HACKER flags: "rxd"
    "TODO: support locking/unlocking etc";
    return true;
  endverb

  verb announce (this none this) owner: HACKER flags: "rxd"
    {event} = args;
    for who in (this:contents())
      `who:tell(event) ! E_VERBNF';
    endfor
  endverb
endobject
