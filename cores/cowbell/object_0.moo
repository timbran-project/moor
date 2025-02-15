object #0
    name: "System Object"
    parent: ROOT
    owner: ARCH_WIZARD
    readable: true

    property arch_wizard (owner: HACKER, flags: "r") = ARCH_WIZARD;
    property builder (owner: HACKER, flags: "r") = BUILDER;
    property first_room (owner: HACKER, flags: "r") = FIRST_ROOM;
    property hacker (owner: HACKER, flags: "r") = HACKER;
    property login (owner: HACKER, flags: "r") = LOGIN;
    property password (owner: HACKER, flags: "r") = PASSWORD;
    property player (owner: HACKER, flags: "r") = PLAYER;
    property programmer (owner: HACKER, flags: "r") = PROGRAMMER;
    property room (owner: HACKER, flags: "r") = ROOM;
    property root (owner: HACKER, flags: "r") = ROOT;
    property string (owner: HACKER, flags: "r") = STRING;
    property wizard (owner: HACKER, flags: "r") = WIZARD;

    verb do_login_command (this none this) owner: ARCH_WIZARD flags: "rxd"
        return #2;
    endverb
endobject
