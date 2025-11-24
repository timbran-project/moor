object CAT_KIBBLE
  name: "Henri's premium kibble"
  parent: THING
  location: KIBBLE_CUPBOARD
  owner: ARCH_WIZARD
  readable: true

  override aliases = {"kibble", "cat food", "food", "premium kibble"};
  override description = "A bag of premium cat kibble, the kind Henri grudgingly accepts. The label reads 'Gourmet Feline Cuisine - Construction Site Edition'.";
  override import_export_hierarchy = {"initial"};
  override import_export_id = "cat_kibble";
endobject
