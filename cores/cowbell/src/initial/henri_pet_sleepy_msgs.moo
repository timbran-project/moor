object HENRI_PET_SLEEPY_MSGS
  name: "Henri Sleepy Pet Messages"
  parent: MSG_BAG
  owner: ARCH_WIZARD
  readable: true

  override entries = {
    {
      <SUB, .capitalize = true, .type = 'actor>,
      " purrs reluctantly, as if doing you a great favor. \"I suppose this is acceptable. For now.\""
    },
    {
      <SUB, .capitalize = true, .type = 'actor>,
      " leans into the petting for a moment before remembering ",
      <SUB, .type = 'subject>,
      " is supposed to be annoyed. ",
      <SUB, .type = 'subject>,
      " pulls away with a huff."
    },
    {
      <SUB, .capitalize = true, .type = 'actor>,
      " closes ",
      <SUB, .type = 'pos_adj>,
      " eyes and pretends to enjoy it, though you can tell ",
      <SUB, .type = 'subject>,
      " ",
      <SUB, .type = 'verb_be>,
      " just too tired to protest properly."
    },
    {
      <SUB, .capitalize = true, .type = 'actor>,
      " murmurs something that sounds like \"The vibrations are almost as good as the old heating vent... almost.\""
    }
  };
  override import_export_hierarchy = {"initial"};
  override import_export_id = "henri_pet_sleepy_msgs";
endobject