object BRASS_KEY [
  import_export_id -> "brass_key",
  import_export_hierarchy -> {"initial"}
]
  name: "a brass key"
  parent: THING
  location: FIRST_ROOM
  owner: ARCH_WIZARD
  readable: true

  override aliases = {"key", "brass key"};
  override description = "A small brass key with an ornate handle. It looks like it might fit a lock on something nearby.";
endobject
