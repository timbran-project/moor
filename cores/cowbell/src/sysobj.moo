object SYSOBJ
    name: "System Object"
    parent: ROOT
    owner: ARCH_WIZARD
    readable: true

    property arch_wizard (owner: HACKER, flags: "r") = ARCH_WIZARD;
    property block (owner: HACKER, flags: "r") = BLOCK;
    property builder (owner: HACKER, flags: "r") = BUILDER;
    property event (owner: HACKER, flags: "r") = EVENT;
    property first_room (owner: HACKER, flags: "r") = FIRST_ROOM;
    property hacker (owner: HACKER, flags: "r") = HACKER;
    property login (owner: HACKER, flags: "r") = LOGIN;
    property look (owner: HACKER, flags: "r") = LOOK;
    property nothing (owner: HACKER, flags: "r") = NOTHING;
    property password (owner: HACKER, flags: "r") = PASSWORD;
    property player (owner: HACKER, flags: "r") = PLAYER;
    property prog (owner: HACKER, flags: "r") = PROG;
    property room (owner: HACKER, flags: "r") = ROOM;
    property root (owner: HACKER, flags: "r") = ROOT;
    property string (owner: HACKER, flags: "r") = STRING;
    property sub (owner: HACKER, flags: "r") = SUB;
    property sysobj (owner: HACKER, flags: "r") = SYSOBJ;
    property wiz (owner: HACKER, flags: "r") = WIZ;

    verb do_login_command (this none this) owner: ARCH_WIZARD flags: "rxd"
        return $arch_wizard;
    endverb
endobject
