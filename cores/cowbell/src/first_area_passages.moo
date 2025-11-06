object FIRST_AREA_PASSAGES
  name: ""
  parent: RELATION
  owner: ARCH_WIZARD

  property index_587B2F903E6227D040909A269C207D89 (owner: ARCH_WIZARD, flags: "r") = [SECOND_ROOM -> {"019a4c43-597e-7731-9cd7-9ca1d73bf3ad"}];
  property index_8B1721635B57EB1AA7316151A17DB139 (owner: ARCH_WIZARD, flags: "r") = [FIRST_ROOM -> {"019a4c43-597e-7731-9cd7-9ca1d73bf3ad"}];
  property index_E991A23AE79226D1B4792712E4F3F381 (owner: ARCH_WIZARD, flags: "r") = E_TYPE;
  property "tuple_019a4c43-597e-7731-9cd7-9ca1d73bf3ad" (owner: ARCH_WIZARD, flags: "r") = {
    FIRST_ROOM,
    SECOND_ROOM,
    <#37, .is_open = true, .side_a_aliases = {"east", "e"}, .side_a_ambient = true, .side_a_description = "An archway leading east.", .side_a_label = "east", .side_a_room = FIRST_ROOM, .side_b_aliases = {"west", "w"}, .side_b_ambient = true, .side_b_description = "A corridor back west.", .side_b_label = "west", .side_b_room = SECOND_ROOM>
  };

  override import_export_id = "first_area_passages";
endobject