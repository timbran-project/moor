object CAT_KIBBLE
  name: "a can of premium cat kibble"
  parent: THING
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  fertile: true
  readable: true

  override aliases = {"kibble", "cat food", "food", "can", "can of kibble"};
  override description = "A can of premium cat kibble, the kind Henri grudgingly accepts. The label reads 'Gourmet Feline Cuisine - Construction Site Edition'.";
  override import_export_hierarchy = {"initial"};
  override import_export_id = "cat_kibble";
endobject
