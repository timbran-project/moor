object HENRI_PET_SLEEPY_MSGS
  name: "Henri Sleepy Pet Messages"
  parent: MSG_BAG
  owner: #2
  readable: true

  override entries = {
    {<SUB, .type = 'actor, .capitalize = true>, " purrs reluctantly, as if doing you a great favor. \"I suppose this is acceptable. For now.\""},
    {<SUB, .type = 'actor, .capitalize = true>, " leans into the petting for a moment before remembering ", <SUB, .type = 'subject>, " is supposed to be annoyed. ", <SUB, .type = 'subject>, " pulls away with a huff."},
    {<SUB, .type = 'actor, .capitalize = true>, " closes ", <SUB, .type = 'pos_adj>, " eyes and pretends to enjoy it, though you can tell ", <SUB, .type = 'subject>, " is just too tired to protest properly."},
    {<SUB, .type = 'actor, .capitalize = true>, " murmurs something that sounds like \"The vibrations are almost as good as the old heating vent... almost.\""}
  };

  override import_export_id = "henri_pet_sleepy_msgs";
endobject
