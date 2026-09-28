object MAIL_ROOM [
  import_export_id -> "mail_room",
  import_export_hierarchy -> {"initial"}
]
  name: "The Mail Room"
  parent: ROOM
  location: FIRST_AREA
  owner: ARCH_WIZARD
  readable: true

  override aliases (owner: ARCH_WIZARD, flags: "rc") = {"mail room", "mailroom"};
  override description (owner: ARCH_WIZARD, flags: "rc") = "A quiet room lined with rows of sturdy mailboxes. Each one bears a small nameplate.";
endobject
