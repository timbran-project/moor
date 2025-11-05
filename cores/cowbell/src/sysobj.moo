object SYSOBJ
  name: "System Object"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  property ambiguous_match (owner: HACKER, flags: "r") = #-2;
  property arch_wizard (owner: HACKER, flags: "r") = ARCH_WIZARD;
  property area (owner: HACKER, flags: "r") = AREA;
  property builder (owner: HACKER, flags: "r") = BUILDER;
  property dvar (owner: HACKER, flags: "r") = DVAR;
  property event (owner: HACKER, flags: "r") = EVENT;
  property failed_match (owner: HACKER, flags: "r") = #-3;
  property first_area (owner: HACKER, flags: "r") = FIRST_AREA;
  property first_room (owner: HACKER, flags: "r") = FIRST_ROOM;
  property format (owner: HACKER, flags: "r") = FORMAT;
  property hacker (owner: HACKER, flags: "r") = HACKER;
  property html (owner: HACKER, flags: "r") = HTML;
  property int_proto (owner: HACKER, flags: "r") = INT_PROTO;
  property list_proto (owner: HACKER, flags: "r") = LIST_PROTO;
  property local (owner: HACKER, flags: "r") = #-1;
  property login (owner: HACKER, flags: "r") = LOGIN;
  property look (owner: HACKER, flags: "r") = LOOK;
  property match (owner: HACKER, flags: "r") = MATCH;
  property nothing (owner: HACKER, flags: "r") = #-1;
  property passage (owner: HACKER, flags: "r") = PASSAGE;
  property password (owner: HACKER, flags: "r") = PASSWORD;
  property player (owner: HACKER, flags: "r") = PLAYER;
  property prog (owner: HACKER, flags: "r") = PROG;
  property pronouns (owner: HACKER, flags: "r") = PRONOUNS;
  property relation (owner: HACKER, flags: "r") = RELATION;
  property room (owner: HACKER, flags: "r") = ROOM;
  property root (owner: HACKER, flags: "r") = ROOT;
  property str_proto (owner: HACKER, flags: "r") = STR_PROTO;
  property sub (owner: HACKER, flags: "r") = SUB;
  property sysobj (owner: HACKER, flags: "r") = SYSOBJ;
  property thing (owner: HACKER, flags: "r") = THING;
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
    `user.location:confunc(user) ! E_INVIND, E_VERBNF';
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
    "Custom command handler which is capable of handling ambiguous object matches by attempting to find matching verb candidates.";
    "...This code should only be run as a server task...";
    callers() && return E_PERM;
    "Just choose to ignore empty commands...";
    length(args) == 0 && return true;
    command = argstr;
    set_task_perms(player);
    env = player:command_environment(command, ['complex -> true]);
    "Run the parts that need wizard permissions";
    return this:_command_handler(command, env);
  endverb

  verb _command_handler (this none this) owner: ARCH_WIZARD flags: "rxd"
    "The wizard-permissioned portion of the custom command handler";
    caller == this || raise(E_PERM);
    {command, env} = args;
    pc = parse_command(command, env, true);
    if (pc["dobj"] == $ambiguous_match)
      dobj_candidates = pc["ambiguous_dobj"];
    else
      dobj_candidates = {pc["dobj"]};
    endif
    if (pc["iobj"] == $ambiguous_match)
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
    "Dispatch any unmatched action out to the room for potential special handling (furniture, passages, etc.)";
    set_task_perms(player);
    player.location:maybe_handle_command(pc) && return true;
    player:inform_current($event:mk_do_not_understand(player, "I don't understand that."):with_audience('utility));
    return true;
  endverb

  verb server_started (this none this) owner: ARCH_WIZARD flags: "rxd"
    server_log("Core starting...");
    "Issue capability for $login to create players";
    player_class = $login.default_player_class;
    $login.player_setup_capability = $prog:issue_capability(player_class, {'create_child, 'make_player}, 0, 0);
    server_log("Issued player creation capability to $login");
  endverb
endobject