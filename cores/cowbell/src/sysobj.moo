object SYSOBJ
  name: "System Object"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  property ambiguous_match (owner: HACKER, flags: "r") = #-2;
  property arch_wizard (owner: HACKER, flags: "r") = ARCH_WIZARD;
  property block (owner: HACKER, flags: "r") = BLOCK;
  property builder (owner: HACKER, flags: "r") = BUILDER;
  property event (owner: HACKER, flags: "r") = EVENT;
  property failed_match (owner: HACKER, flags: "r") = #-3;
  property first_room (owner: HACKER, flags: "r") = FIRST_ROOM;
  property hacker (owner: HACKER, flags: "r") = HACKER;
  property html (owner: HACKER, flags: "r") = HTML;
  property int_proto (owner: HACKER, flags: "r") = INT_PROTO;
  property list (owner: HACKER, flags: "r") = LIST;
  property list_proto (owner: HACKER, flags: "r") = LIST_PROTO;
  property login (owner: HACKER, flags: "r") = LOGIN;
  property look (owner: HACKER, flags: "r") = LOOK;
  property match (owner: HACKER, flags: "r") = MATCH;
  property nothing (owner: HACKER, flags: "r") = #-1;
  property local (owner: HACKER, flags: "r") = #-1;
  property password (owner: HACKER, flags: "r") = PASSWORD;
  property player (owner: HACKER, flags: "r") = PLAYER;
  property prog (owner: HACKER, flags: "r") = PROG;
  property room (owner: HACKER, flags: "r") = ROOM;
  property root (owner: HACKER, flags: "r") = ROOT;
  property str_proto (owner: HACKER, flags: "r") = STR_PROTO;
  property sub (owner: HACKER, flags: "r") = SUB;
  property sysobj (owner: HACKER, flags: "r") = SYSOBJ;
  property table (owner: HACKER, flags: "r") = TABLE;
  property thing (owner: HACKER, flags: "r") = THING;
  property title (owner: HACKER, flags: "r") = TITLE;
  property wiz (owner: HACKER, flags: "r") = WIZ;

  override description = "System object containing global properties and core server event handlers.";
  override import_export_id = "sysobj";

  verb do_login_command (this none this) owner: ARCH_WIZARD flags: "rxd"
    "...This code should only be run as a server task...";
    callers() && return E_PERM;
    args = $login:parse_command(@args);
    return $login:((args[1]))(@listdelete(args, 1));
  endverb

  verb "user_created user_connected" (this none this) owner: HACKER flags: "rxd"
    "...This code should only be run as a server task...";
    callers() && return E_PERM;
    user = args[1];
    if (user < #0)
      return;
    endif
    fork (0)
      `user:confunc() ! E_VERBNF';
    endfork
    `user.location:confunc(user) ! E_VERBNF';
    `user:anyconfunc() ! E_VERBNF';
  endverb

  verb "user_disconnected user_client_disconnected" (this none this) owner: HACKER flags: "rxd"
    "...This code should only be run as a server task...";
    callers() && return E_PERM;
    user = args[1];
    if (user < #0)
      return;
    endif
    fork (0)
      `user.location:disfunc(user) ! E_INVIND, E_VERBNF';
    endfork
    `user:disfunc() ! E_VERBNF';
  endverb

  verb user_reconnected (this none this) owner: HACKER flags: "rxd"
    "...This code should only be run as a server task...";
    callers() && return E_PERM;
    user = args[1];
    if (user < #0)
      return;
    endif
    fork (0)
      `user.location:reconfunc(user) ! E_INVIND, E_VERBNF';
    endfork
    fork (0)
      `user:reconfunc() ! E_VERBNF';
    endfork
    `user:anyconfunc() ! E_VERBNF';
  endverb

  verb do_command (this none this) owner: ARCH_WIZARD flags: "rxd"
    length(args) == 0 && return true;
    command = args:join(" ");
    pc = parse_command(command, {player, @player.contents, player.location, @player.location.contents}, true);
    env = {player, @player.contents, player.location, @player.location.contents};
    if (pc["dobj"] == #-2)
      dobj_candidates = pc["ambiguous_dobj"];
    else
      dobj_candidates = {pc["dobj"]};
    endif
    if (pc["iobj"] == #-2)
      iobj_candidates = pc["ambiguous_iobj"];
    else
      iobj_candidates = {pc["iobj"]};
    endif
    for dobj in (dobj_candidates)
      for iobj in (iobj_candidates)
        test_pc = pc;
        test_pc["dobj"] = dobj;
        test_pc["iobj"] = iobj;
        vm_matches = find_command_verb(test_pc, env);
        if (vm_matches)
          for m in (vm_matches)
            {target, verbspec} = m;
            {def, flags, verbnames, v} = verbspec;
            dispatch_command_verb(target, v, test_pc);
            return true;
          endfor
          return;
        endif
      endfor
    endfor
    notify(connection(), "I don't understand that.");
    return true;
  endverb

endobject
