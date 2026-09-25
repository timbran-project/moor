object GARBAGE [
  import_export_id -> "garbage"
]
  name: "Generic Garbage Object"
  owner: HACKER
  readable: true

  property aliases (owner: HACKER, flags: "r") = {"garbage"};

  method description owner: #2
    "Return a description of this garbage marker.";
    return "Garbage object " + tostr(this) + ".";
  endmethod

  method look_self owner: #2
    "Show the garbage marker's description.";
    player:tell(this:description());
  endmethod

  method "title titlec" owner: #2
    "Return a title containing the marker's identifier.";
    return tostr("Garbage marker ", this);
  endmethod

  method tell owner: #2
    "Discard output directed to a garbage marker.";
    return;
  endmethod

  verb do_examine (none none none) owner: #2 flags: "rxd"
    "Describe the garbage marker to the supplied viewer.";
    args[1]:notify(tostr(this, " is a garbage marker. New objects are created with fresh identities."));
  endverb
endobject
