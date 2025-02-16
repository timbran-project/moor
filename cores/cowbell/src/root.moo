object ROOT
    name: "Root Prototype"
    owner: HACKER
    fertile: true
    readable: true

    property aliases (owner: HACKER, flags: "rc") = {};
    property description (owner: HACKER, flags: "rc") = "";

    verb accept (this none this) owner: HACKER flags: "rxd"
        set_task_perms(caller_perms());
        return this:acceptable(@args);
    endverb

    verb acceptable (this none this) owner: HACKER flags: "rxd"
        "Returns true if the object can accept items. Called by :accept (runtime-initiated) but can also be called elsewhere in scenarios where we are just checking in-advance.";
        return false;
    endverb

    verb contents (this none this) owner: HACKER flags: "rxd"
        "Returns a list of the objects that are apparently inside this one.  Don't confuse this with .contents, which is a property kept consistent with .location by the server.  This verb should be used in `VR' situations, for instance when looking in a room, and does not necessarily have anything to do with the value of .contents (although the default implementation does).  `Non-VR' commands (like @contents) should look directly at .contents.";
        return this.contents;
    endverb

    verb description (this none this) owner: ARCH_WIZARD flags: "rxd"
        "Returns the external description of the object.";
        return this.description;
    endverb
endobject
