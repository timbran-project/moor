object GARBAGE
  name: "Generic Garbage Object"
  owner: HACKER
  readable: true

  property aliases (owner: HACKER, flags: "r") = {"garbage"};
  property import_export_id (owner: HACKER, flags: "r") = "garbage";

  method description owner: #2
    return "Garbage object " + tostr(this) + ".";
  endmethod

  method look_self owner: #2
    player:tell(this:description());
  endmethod

  method "title titlec" owner: #2
    return tostr("Recyclable ", this);
  endmethod

  method tell owner: #2
    return;
  endmethod

  verb do_examine (none none none) owner: #2 flags: "rxd"
    args[1]:notify(tostr(this, " is a garbage object, ready for reuse."));
  endverb
endobject
