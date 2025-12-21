object HENRI_PET_GROUCHY_MSGS
  name: "Henri Grouchy Pet Messages"
  parent: MSG_BAG
  owner: ARCH_WIZARD
  readable: true

  override entries = {
    {
      <SUB, .capitalize = true, .type = 'actor>,
      " flattens ",
      <SUB, .type = 'pos_adj>,
      " ears and gives you a look of pure betrayal. \"I was in the middle of a very important sulk,\" ",
      <SUB, .type = 'subject>,
      " seems to say."
    },
    {
      <SUB, .capitalize = true, .type = 'actor>,
      " allows exactly two pets before pulling away with an offended sniff. \"That's quite enough of that,\" ",
      <SUB, .type = 'pos_adj>,
      " posture suggests."
    },
    {
      <SUB, .capitalize = true, .type = 'actor>,
      " tolerates the petting for precisely three seconds before ",
      <SUB, .type = 'pos_adj>,
      " tail starts twitching violently. \"Are you quite finished?\""
    },
    {
      <SUB, .capitalize = true, .type = 'actor>,
      " turns ",
      <SUB, .type = 'pos_adj>,
      " head away dramatically. \"I'm not some common housecat to be petted at your whim. I have standards, you know.\""
    },
    {
      <SUB, .capitalize = true, .type = 'actor>,
      " lets out a long-suffering sigh. \"Fine, if you must. But don't expect me to enjoy it.\""
    }
  };
  override import_export_hierarchy = {"initial"};
  override import_export_id = "henri_pet_grouchy_msgs";
endobject