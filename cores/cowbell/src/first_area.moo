object FIRST_AREA
  name: "The First Area"
  parent: AREA
  owner: ARCH_WIZARD
  readable: true

  property "passage_edge_#12_#39" (owner: ARCH_WIZARD, flags: "rc") = <#37, {FIRST_ROOM, "east", {"east", "e"}, "An archway leading east.", true, SECOND_ROOM, "west", {"west", "w"}, "A corridor back west.", true, true}>;

  override description = "Default area container for the initial rooms.";
  override import_export_id = "first_area";
endobject