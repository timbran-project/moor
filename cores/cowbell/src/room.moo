object ROOM
    name: "Generic Room"
    parent: ROOT
    owner: HACKER

    verb say (any any any) owner: HACKER flags: "rxd"
        event = $event:mk_say(player, false, false, player.location, $sub:nc(), " ", $sub:self_alt("say", "says"), " \"", argstr, "\"");
        for who in (this:contents())
            who:isa($player) && who:tell(event);
        endfor
    endverb
endobject
