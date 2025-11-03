object FIRST_AREA
  name: "The First Area"
  parent: AREA
  owner: ARCH_WIZARD
  readable: true

  property "passage_edge_#12_#39" (owner: ARCH_WIZARD, flags: "rc") = <#37, [side_a_room -> FIRST_ROOM, side_a_label -> "east", side_a_aliases -> {"east", "e"}, side_a_description -> "An archway leading east.", side_a_ambient -> true, side_b_room -> SECOND_ROOM, side_b_label -> "west", side_b_aliases -> {"west", "w"}, side_b_description -> "A corridor back west.", side_b_ambient -> true, is_open -> true]>;

  override description = "Default area container for the initial rooms.";
  override import_export_id = "first_area";
endobject
