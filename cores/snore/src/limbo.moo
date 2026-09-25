object LIMBO [
  import_export_id -> "limbo"
]
  name: "Limbo"
  parent: ROOT_CLASS
  owner: #2
  readable: true

  override aliases (owner: #2, flags: "rc") = {"The Body Bag"};
  override object_size (owner: HACKER, flags: "r") = {2330, 1084848672};

  method acceptable owner: #2
    "Accept disconnected players only.";
    const what = args[1];
    return is_player(what) && !(what in connected_players());
  endmethod

  method confunc owner: #2
    "Move a connecting player from limbo to its home or the player start. System hook only.";
    caller == #0 || raise(E_PERM);
    let {who} = args;
    "this:eject(who)";
    let home = who.home;
    if (!$recycler:valid(home))
      clear_property(who, "home");
      home = who.home;
      if (!$recycler:valid(home))
        home = who.home = $player_start;
      endif
    endif
    "Modified 08-22-98 by TheCat to foil people who manually set their home to places they shouldn't.";
    if (!home:acceptable(who) || !home:accept_for_abode(who))
      home = $player_start;
    endif
    try
      move(who, home);
    except (ANY)
      move(who, $player_start);
    endtry
    who.location:announce_all_but({who}, who.name, " has connected.");
  endmethod

  method who_location_msg owner: HACKER
    "Use the player-start description for a player in limbo.";
    return $player_start:who_location_msg(@args);
  endmethod

  method moveto owner: HACKER
    "Don't go anywhere.";
  endmethod

  method eject owner: #2
    "Move a controlled wizard home, otherwise use the normal ejection policy.";
    let what;
    if ($perm_utils:controls(caller_perms(), this))
      what = args[1];
      if (what.wizard && what.location == this)
        move(what, what.home);
      else
        return pass(@args);
      endif
    endif
  endmethod
endobject
