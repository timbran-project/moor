object HENRI_PET_SLEEPY_MSGS
  name: "Henri Sleepy Pet Messages"
  parent: MSG_BAG
  owner: ARCH_WIZARD
  readable: true

  override entries = {
    {
      <#19, .type = 'actor, .capitalize = true>,
      " purrs reluctantly, as if doing you a great favor. \"I suppose this is acceptable. For now.\""
    },
    {
      <#19, .type = 'actor, .capitalize = true>,
      " leans into the petting for a moment before remembering ",
      <#19, .type = 'subject>,
      " is supposed to be annoyed. ",
      <#19, .type = 'subject>,
      " pulls away with a huff."
    },
    {
      <#19, .type = 'actor, .capitalize = true>,
      " closes ",
      <#19, .type = 'pos_adj>,
      " eyes and pretends to enjoy it, though you can tell ",
      <#19, .type = 'subject>,
      " ",
      <#19, .type = 'verb_be>,
      " just too tired to protest properly."
    },
    {
      <#19, .type = 'actor, .capitalize = true>,
      " murmurs something that sounds like \"The vibrations are almost as good as the old heating vent... almost.\""
    }
  };
  override import_export_hierarchy = {"initial"};
  override import_export_id = "henri_pet_sleepy_msgs";
endobject