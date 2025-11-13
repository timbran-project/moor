object FIRST_AREA_PASSAGES
  name: "First Area Passages"
  parent: RELATION
  owner: ARCH_WIZARD

  property index_587B2F903E6227D040909A269C207D89 (owner: ARCH_WIZARD, flags: "r") = [SECOND_ROOM -> {"019a734f-0aa2-7f60-b3f2-8f066156db03"}];
  property index_6CEEFF254DDBA55D88FEC5C1FD2B967F (owner: ARCH_WIZARD, flags: "r") = [#0001DB-9A6FCA8482 -> {"019a734f-0a9c-7100-8bfc-113dba46e3a0"}];
  property index_8B1721635B57EB1AA7316151A17DB139 (owner: ARCH_WIZARD, flags: "r") = [
    FIRST_ROOM -> {
      "019a734f-0a9c-7100-8bfc-113dba46e3a0",
      "019a734f-0aa1-73d1-bb1b-e5295c91f35d",
      "019a734f-0aa2-7f60-b3f2-8f066156db03"
    }
  ];
  property index_CBDD88127C22202E7C735506679FFBDD (owner: ARCH_WIZARD, flags: "r") = [#00022F-9A6FCA8482 -> {"019a734f-0aa1-73d1-bb1b-e5295c91f35d"}];
  property index_E991A23AE79226D1B4792712E4F3F381 (owner: ARCH_WIZARD, flags: "r") = E_TYPE;
  property "tuple_019a734f-0a9c-7100-8bfc-113dba46e3a0" (owner: ARCH_WIZARD, flags: "r") = {
    FIRST_ROOM,
    #0001DB-9A6FCA8482,
    <#37, .side_b_label = "north", .side_b_aliases = {"north", "n"}, .side_a_room = FIRST_ROOM, .side_b_room = #0001DB-9A6FCA8482, .is_open = true, .side_a_aliases = {"south", "s"}, .side_a_ambient = true, .side_a_description = "To the south, the warm glow of a reading room beckons", .side_a_label = "south", .side_b_ambient = true, .side_b_description = "">
  };
  property "tuple_019a734f-0aa1-73d1-bb1b-e5295c91f35d" (owner: ARCH_WIZARD, flags: "r") = {
    FIRST_ROOM,
    #00022F-9A6FCA8482,
    <#37, .side_b_label = "south", .side_b_aliases = {"south", "s"}, .side_a_room = FIRST_ROOM, .side_b_room = #00022F-9A6FCA8482, .is_open = true, .side_a_aliases = {"north", "n"}, .side_a_ambient = true, .side_a_description = "To the north, a hallway leads deeper into the hotel", .side_a_label = "north", .side_b_ambient = true, .side_b_description = "">
  };
  property "tuple_019a734f-0aa2-7f60-b3f2-8f066156db03" (owner: ARCH_WIZARD, flags: "r") = {
    FIRST_ROOM,
    SECOND_ROOM,
    <#37, .side_b_label = "west", .side_b_aliases = {"west", "w"}, .side_a_room = FIRST_ROOM, .side_b_room = SECOND_ROOM, .is_open = true, .side_a_aliases = {"east", "e"}, .side_a_ambient = true, .side_a_description = "To the east, the hotel's main entrance awaits", .side_a_label = "east", .side_b_ambient = true, .side_b_description = "A corridor back west.">
  };

  override import_export_id = "first_area_passages";
endobject