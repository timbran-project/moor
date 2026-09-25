object DEFAULT_GUEST [
  import_export_id -> "default_guest"
]
  name: "Guest"
  parent: GUEST
  location: PLAYER_START
  owner: HACKER
  player: true
  readable: true

  override aliases (owner: HACKER, flags: "rc") = {"Guest", "guest"};
  override description (owner: HACKER, flags: "rc") = {"By definition, guests appear nondescript."};
  override gender (owner: HACKER, flags: "rc") = "neuter";
  override home (owner: HACKER, flags: "rc") = PLAYER_START;
  override password (owner: #2, flags: "") = 0;
endobject
