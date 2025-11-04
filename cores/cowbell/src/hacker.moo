object HACKER
  name: "Hacker"
  parent: PROG
  location: FIRST_ROOM
  owner: HACKER
  readable: true
  player: true
  programmer: true

  override description = "System identity used as the owner of verbs that should execute with non-wizard permissions. Provides a permission boundary below wizard level but with programmer/build capabilities for verbs to run under.";
  override import_export_id = "hacker";
endobject