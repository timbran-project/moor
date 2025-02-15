object #0
    name: "System Object"
    parent: ROOT
    owner: WIZARD
    readable: true

    property room (owner: WIZARD, flags: "r") = ROOM;
    property root (owner: WIZARD, flags: "r") = ROOT;
    property string (owner: WIZARD, flags: "r") = STRING;
    property wizard (owner: WIZARD, flags: "r") = WIZARD;

    verb do_login_command (this none this) owner: WIZARD flags: "rxd"
        return #3;
    endverb
endobject
