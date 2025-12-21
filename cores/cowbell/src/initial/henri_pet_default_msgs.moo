object HENRI_PET_DEFAULT_MSGS
  name: "Henri Default Pet Messages"
  parent: MSG_BAG
  owner: ARCH_WIZARD
  readable: true

  override entries = {
    {
      <SUB, .capitalize = true, .type = 'actor>,
      " sighs but doesn't pull away immediately. \"I suppose I'm getting used to this indignity.\""
    },
    {
      <SUB, .capitalize = true, .type = 'actor>,
      " tolerates the petting with weary resignation. \"At least your technique has improved slightly.\""
    },
    {
      <SUB, .capitalize = true, .type = 'actor>,
      " leans into the petting for a moment before remembering ",
      <SUB, .type = 'subject>,
      " is supposed to be annoyed."
    },
    {
      <SUB, .capitalize = true, .type = 'actor>,
      " gives you a look that says \"I'm only allowing this because the alternative is listening to more hammering.\""
    },
    {
      <SUB, .capitalize = true, .type = 'actor>,
      " tolerates your attention with the weary resignation of a cat who has seen better days and better accommodations."
    },
    {
      <SUB, .capitalize = true, .type = 'actor>,
      " flicks an ear in your direction. \"If you're quite done disrupting my brooding session...\""
    }
  };
  override import_export_hierarchy = {"initial"};
  override import_export_id = "henri_pet_default_msgs";
endobject