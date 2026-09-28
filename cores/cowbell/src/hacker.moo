object HACKER [
  import_export_id -> "hacker"
]
  name: "Hacker"
  parent: PLAYER
  location: PROTOTYPE_BOX
  owner: HACKER
  player: true
  programmer: true
  readable: true

  override authoring_features (owner: ARCH_WIZARD, flags: "") = PROG_FEATURES;
  override description (owner: HACKER, flags: "rc") = "System identity used as the owner of verbs that should execute with non-wizard permissions. Provides a permission boundary below wizard level but with programmer/build capabilities for verbs to run under. This account cannot be logged into directly.";
  override is_builder (owner: ARCH_WIZARD, flags: "") = true;
endobject
