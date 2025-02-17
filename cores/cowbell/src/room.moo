object ROOM
    name: "Generic Room"
    parent: ROOT
    owner: HACKER

    verb say (any any any) owner: HACKER flags: "rxd"
        event = $event:mk_say(player, false, false, player.location, $sub:nc(), " says, \"", argstr, "\"");
        player:tell(event);
    endverb
endobject
