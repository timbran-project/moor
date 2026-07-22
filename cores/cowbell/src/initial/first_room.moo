object FIRST_ROOM [
  import_export_id -> "first_room",
  import_export_hierarchy -> {"initial"}
]
  name: "The First Room"
  parent: ROOM
  location: FIRST_AREA
  owner: ARCH_WIZARD
  readable: true

  override description = "You are in the very First Room. Someone needs to provide a description.";
endobject
