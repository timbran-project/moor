object FIRST_AREA
  name: "The First Area"
  parent: AREA
  owner: ARCH_WIZARD
  readable: true

  override description = "Default area container for the initial rooms.";
  override import_export_hierarchy = {"initial"};
  override import_export_id = "first_area";
  override passages_rel (owner: ARCH_WIZARD, flags: "rc") = FIRST_AREA_PASSAGES;
endobject