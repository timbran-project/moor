object HACKER
  name: "Hacker"
  parent: PROG
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  override description = "System identity used as the owner of verbs that should execute with non-wizard permissions. Provides a permission boundary below wizard level.";
  override import_export_id = "hacker";
endobject