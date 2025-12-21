object FIRST_AREA_PASSAGES
  name: "First Area Passages"
  parent: RELATION
  owner: ARCH_WIZARD

  property index_3E6D8CF1D161C6ABB8952FAC01B152A9 (owner: ARCH_WIZARD, flags: "r") = [#000064-9B1D3F893C -> {"019b1d47-1bf4-7a63-9d30-30da579df023"}];
  property index_FA8DC861CB6614C74FBA2153C9D2D42C (owner: ARCH_WIZARD, flags: "r") = [FIRST_ROOM -> {"019b1d47-1bf4-7a63-9d30-30da579df023"}];
  property "tuple_019b1d47-1bf4-7a63-9d30-30da579df023" (owner: ARCH_WIZARD, flags: "r") = {
    FIRST_ROOM,
    #000064-9B1D3F893C,
    <PASSAGE, .side_a_room = FIRST_ROOM, .side_b_room = #000064-9B1D3F893C, .side_a_aliases = {"north", "n"}, .side_b_aliases = {"south", "s"}, .side_a_label = "north", .side_b_label = "south", .is_open = true, .side_a_ambient = true, .side_a_arrive_msg = {}, .side_a_description = "", .side_a_leave_msg = {}, .side_a_prose_style = 'fragment, .side_a_departure_phrase = "", .side_a_arrival_phrase = "", .side_b_ambient = true, .side_b_arrive_msg = {}, .side_b_description = "", .side_b_leave_msg = {}, .side_b_prose_style = 'fragment, .side_b_departure_phrase = "", .side_b_arrival_phrase = "">
  };

  override import_export_hierarchy = {"initial"};
  override import_export_id = "first_area_passages";
endobject