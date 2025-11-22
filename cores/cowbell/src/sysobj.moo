object SYSOBJ
  name: "System Object"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  property actor (owner: HACKER, flags: "r") = ACTOR;
  property ambiguous_match (owner: HACKER, flags: "r") = #-2;
  property ansi (owner: HACKER, flags: "r") = ANSI;
  property arch_wizard (owner: HACKER, flags: "r") = ARCH_WIZARD;
  property architects_compass (owner: HACKER, flags: "r") = ARCHITECTS_COMPASS;
  property area (owner: HACKER, flags: "r") = AREA;
  property bg_ticks (owner: HACKER, flags: "r") = 300000;
  property builder_features (owner: HACKER, flags: "r") = BUILDER_FEATURES;
  property builder_prototypes (owner: HACKER, flags: "r") = {ROOM, THING, WEARABLE, CONTAINER, AREA};
  property container (owner: HACKER, flags: "r") = CONTAINER;
  property data_visor (owner: HACKER, flags: "r") = DATA_VISOR;
  property dvar (owner: HACKER, flags: "r") = DVAR;
  property event (owner: HACKER, flags: "r") = EVENT;
  property event_receiver (owner: HACKER, flags: "r") = EVENT_RECEIVER;
  property examination (owner: HACKER, flags: "r") = EXAMINATION;
  property failed_match (owner: HACKER, flags: "r") = #-3;
  property fg_ticks (owner: HACKER, flags: "r") = 600000;
  property first_area (owner: HACKER, flags: "r") = FIRST_AREA;
  property first_room (owner: HACKER, flags: "r") = FIRST_ROOM;
  property format (owner: HACKER, flags: "r") = FORMAT;
  property grant_utils (owner: HACKER, flags: "r") = GRANT_UTILS;
  property hacker (owner: HACKER, flags: "r") = HACKER;
  property help_utils (owner: HACKER, flags: "r") = HELP_UTILS;
  property html (owner: HACKER, flags: "r") = HTML;
  property int_proto (owner: HACKER, flags: "r") = INT_PROTO;
  property list_proto (owner: HACKER, flags: "r") = LIST_PROTO;
  property henri (owner: HACKER, flags: "r") = HENRI;
  property henri_look_self_msgs (owner: HACKER, flags: "r") = HENRI_LOOK_SELF_MSGS;
  property llm_agent (owner: HACKER, flags: "r") = LLM_AGENT;
  property llm_agent_tool (owner: HACKER, flags: "r") = LLM_AGENT_TOOL;
  property llm_client (owner: HACKER, flags: "r") = LLM_CLIENT;
  property llm_room_observer (owner: HACKER, flags: "r") = LLM_ROOM_OBSERVER;
  property llm_task (owner: HACKER, flags: "r") = LLM_TASK;
  property llm_wearable (owner: HACKER, flags: "r") = LLM_WEARABLE;
  property local (owner: HACKER, flags: "r") = #-1;
  property msg_bag (owner: HACKER, flags: "r") = MSG_BAG;
  property login (owner: HACKER, flags: "r") = LOGIN;
  property look (owner: HACKER, flags: "r") = LOOK;
  property match (owner: HACKER, flags: "r") = MATCH;
  property mr_welcome (owner: HACKER, flags: "r") = MR_WELCOME;
  property nothing (owner: HACKER, flags: "r") = #-1;
  property obj_utils (owner: HACKER, flags: "r") = OBJ_UTILS;
  property passage (owner: HACKER, flags: "r") = PASSAGE;
  property password (owner: HACKER, flags: "r") = PASSWORD;
  property player (owner: HACKER, flags: "r") = PLAYER;
  property prog_features (owner: HACKER, flags: "r") = PROG_FEATURES;
  property prog_utils (owner: HACKER, flags: "r") = PROG_UTILS;
  property pronouns (owner: HACKER, flags: "r") = PRONOUNS;
  property property (owner: HACKER, flags: "r") = PROPERTY;
  property prototype_box (owner: HACKER, flags: "r") = PROTOTYPE_BOX;
  property relation (owner: HACKER, flags: "r") = RELATION;
  property room (owner: HACKER, flags: "r") = ROOM;
  property root (owner: HACKER, flags: "r") = ROOT;
  property scheduled_task (owner: HACKER, flags: "r") = SCHEDULED_TASK;
  property scheduler (owner: HACKER, flags: "r") = SCHEDULER;
  property server_options (owner: ARCH_WIZARD, flags: "r") = SERVER_OPTIONS;
  property social_features (owner: HACKER, flags: "r") = SOCIAL_FEATURES;
  property str_proto (owner: HACKER, flags: "r") = STR_PROTO;
  property sub (owner: HACKER, flags: "r") = SUB;
  property sub_utils (owner: HACKER, flags: "r") = SUB_UTILS;
  property sysobj (owner: HACKER, flags: "r") = SYSOBJ;
  property thing (owner: HACKER, flags: "r") = THING;
  property verb (owner: HACKER, flags: "r") = VERB;
  property wearable (owner: HACKER, flags: "r") = WEARABLE;
  property wiz_features (owner: HACKER, flags: "r") = WIZ_FEATURES;

  override description = "System object containing global properties and core server event handlers.";
  override import_export_id = "sysobj";

  verb do_login_command (this none this) owner: ARCH_WIZARD flags: "rxd"
    "...This code should only be run as a server task, but we'll let wizards poke at it...";
    callers() && !caller_perms().wizard && return E_PERM;
    args = $login:parse_command(@args);
    return $login:((args[1]))(@listdelete(args, 1));
  endverb

  verb "user_created user_connected" (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Called by the server when a user connects...";
    "...This code should only be run as a server task, but we'll let wizards poke at it...";
    callers() && !caller_perms().wizard && return E_PERM;
    user = args[1];
    set_task_perms(user);
    if (user < #0)
      return;
    endif
    fork (0)
      `user:confunc() ! E_VERBNF';
    endfork
    `user.location:confunc(user) ! E_INVIND, E_VERBNF';
    "Welcome new players after room setup";
    if (verb == "user_created")
      `$login:welcome_new_player(user) ! E_VERBNF';
    endif
    `user:anyconfunc() ! E_VERBNF';
  endverb

  verb "user_disconnected user_client_disconnected" (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Called when a user disconnects...";
    "...This code should only be run as a server task, but we'll let wizards poke at it...";
    callers() && !caller_perms().wizard && return E_PERM;
    user = args[1];
    set_task_perms(user);
    if (user < #0)
      return;
    endif
    fork (0)
      `user.location:disfunc(user) ! E_INVIND, E_VERBNF';
    endfork
    `user:disfunc() ! E_VERBNF';
  endverb

  verb user_reconnected (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Called when a user re-connects to the system from another session... Which isn't really a thing in mooR, but here for compatibility...";
    "...This code should only be run as a server task, but we'll let wizards poke at it...";
    callers() && !caller_perms().wizard && return E_PERM;
    user = args[1];
    set_task_perms(user);
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
    "...This code should only be run as a server task, but we'll let wizards poke at it...";
    callers() && !caller_perms().wizard && return E_PERM;
    "Just choose to ignore empty commands...";
    length(args) == 0 && return true;
    command = argstr;
    set_task_perms(player);
    env = player:match_environment(command, ['complex -> true]);
    "Run the parts that need wizard permissions";
    "We let this throw otherwise errors in commands would not propagate.";
    return this:_command_handler(command, env);
  endverb

  verb _command_handler (this none this) owner: ARCH_WIZARD flags: "rxd"
    "The wizard-permissioned portion of the custom command handler";
    caller == this || raise(E_PERM);
    {command, match_env} = args;
    "Parse command using match environment (all visible objects for dobj/iobj matching)";
    pc = parse_command(command, match_env, true);
    "Get command environment (only player and location for primary verb searching)";
    command_env = player:command_environment();
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
        vm_matches = find_command_verb(test_pc, command_env);
        if (vm_matches)
          for m in (vm_matches)
            {target, verbspec} = m;
            {def, flags, verbnames, v} = verbspec;
            dispatch_command_verb(target, v, test_pc);
            return true;
          endfor
        endif
      endfor
    endfor
    "Dispatch any unmatched action out to the room for potential special handling (furniture, passages, etc.)";
    set_task_perms(player);
    player.location:maybe_handle_command(pc) && return true;
    player:inform_current($event:mk_do_not_understand(player, "I don't know how to do that."):with_audience('utility));
    return true;
  endverb

  verb bf_recycle (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Intercept recycle() to enforce permission checking through :destroy.";
    "Allows direct recycle() if: wizard, object not rooted in #1, or called from :destroy";
    {target} = args;
    "If not an object, let builtin raise the appropriate error";
    if (typeof(target) != OBJ)
      return recycle(target);
    endif
    "IMPORTANT: Run as the caller, so that the right permissions are applied...";
    set_task_perms(caller_perms());
    "Wizards can recycle anything";
    if (caller_perms().wizard)
      return recycle(target);
    endif
    "Objects not rooted in $root don't have :destroy, allow direct recycle";
    if (!isa(target, $root))
      return recycle(target);
    endif
    "Check if we're being called from :destroy by examining call stack, to avoid cyclic agony and pain...";
    for frame in (callers())
      if (frame[2] == "destroy" && frame[1] == target)
        return recycle(target);
      endif
    endfor
    "Not authorized - must go through :destroy for permission checking";
    raise(E_PERM);
  endverb

  verb list_builder_prototypes (this none this) owner: HACKER flags: "rxd"
    "Return list of builder prototypes with descriptions";
    result = {};
    for proto in (this.builder_prototypes)
      if (valid(proto))
        proto_name = tostr(proto);
        "Try to get sysobj name";
        for prop in (properties(this))
          if (this.(prop) == proto)
            proto_name = "$" + prop;
            break;
          endif
        endfor
        desc = `proto.description ! ANY => "(no description)"';
        result = {@result, ["object" -> tostr(proto), "name" -> proto_name, "description" -> desc]};
      endif
    endfor
    return result;
  endverb

  verb server_started (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Called on server start to kick off initial state after being out of existence for a bit...";
    "...This code should only be run as a server task, but we'll let wizards poke at it...";
    callers() && !caller_perms().wizard && return E_PERM;
    server_log("Core starting...");
    "Issue capability for $login to create players";
    player_class = $login.default_player_class;
    $login.player_setup_capability = $player:issue_capability(player_class, {'create_child, 'make_player}, 0, 0);
    server_log("Issued player creation capability to $login");
    "Resume scheduler if needed";
    $scheduler:resume_if_needed();
  endverb

  verb handle_uncaught_error (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Called when there's an uncaught error in a task...";
    if (callers() && !caller_perms().wizard)
        server_log("Illegal call to `handle_uncaught_error` from " + toliteral(callers()));
        return;
    endif
    {code, msg, value, stack, traceback} = args;
    server_log("Uncaught error: " + toliteral(code) + "(" + toliteral(msg) + ") (value: " + toliteral(value) + ")\n" + toliteral(traceback));
    "Let the player do something with it if it can...";
    return `player:(verb)(@args) ! ANY';
  endverb

  verb _log (this none this) owner: ARCH_WIZARD flags: "rxd"
    callers() && !caller_perms().wizard && return E_PERM;
    server_log(@args);
  endverb
endobject
