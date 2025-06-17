object SYSOBJ
  name: "System Object"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  property failed_match (owner: HACKER, flags: "r") = FAILED_MATCH;
  property ambiguous (owner: HACKER, flags: "r") = AMBIGUOUS;
  property nothing (owner: HACKER, flags: "r") = NOTHING;
  property sysobj (owner: HACKER, flags: "r") = SYSOBJ;
  property root (owner: HACKER, flags: "r") = ROOT;
  property arch_wizard (owner: HACKER, flags: "r") = ARCH_WIZARD;
  property room (owner: HACKER, flags: "r") = ROOM;
  property player (owner: HACKER, flags: "r") = PLAYER;
  property builder (owner: HACKER, flags: "r") = BUILDER;
  property prog (owner: HACKER, flags: "r") = PROG;
  property hacker (owner: HACKER, flags: "r") = HACKER;
  property wiz (owner: HACKER, flags: "r") = WIZ;
  property str_proto (owner: HACKER, flags: "r") = STR_PROTO;
  property password (owner: HACKER, flags: "r") = PASSWORD;
  property first_room (owner: HACKER, flags: "r") = FIRST_ROOM;
  property login (owner: HACKER, flags: "r") = LOGIN;
  property event (owner: HACKER, flags: "r") = EVENT;
  property sub (owner: HACKER, flags: "r") = SUB;
  property block (owner: HACKER, flags: "r") = BLOCK;
  property look (owner: HACKER, flags: "r") = LOOK;
  property list_proto (owner: HACKER, flags: "r") = LIST_PROTO;
  property thing (owner: HACKER, flags: "r") = THING;

  verb do_login_command (this none this) owner: ARCH_WIZARD flags: "rxd"
    "...This code should only be run as a server task...";
    callers() && return E_PERM;
    global args = $login:parse_command(@args);
    return $login:((args[1]))(@listdelete(args, 1));
  endverb

  verb "user_created user_connected" (this none this) owner: HACKER flags: "rxd"
    user = args[1];
    if (callers())
      raise(E_PERM);
    endif
    if (args[1] < #0)
      return;
    endif
    fork (0)
      `user:confunc() ! E_VERBNF';
    endfork
    `user.location:confunc(user) ! E_VERBNF';
    `user:anyconfunc() ! E_VERBNF';
  endverb

  verb "user_disconnected user_client_disconnected" (this none this) owner: HACKER flags: "rxd"
    if (callers())
      return;
    endif
    user = args[1];
    fork (0)
      `user.location:disfunc(user) ! E_INVIND, E_VERBNF';
    endfork
    `user:disfunc() ! E_VERBNF';
  endverb

  verb user_reconnected (this none this) owner: HACKER flags: "rxd"
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
endobject
