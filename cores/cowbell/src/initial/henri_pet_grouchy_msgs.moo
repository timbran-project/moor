object HENRI_PET_GROUCHY_MSGS
  name: "Henri Grouchy Pet Messages"
  parent: MSG_BAG
  owner: #2
  readable: true

  override entries = {
    {<SUB, .type = 'actor, .capitalize = true>, " flattens ", <SUB, .type = 'pos_adj>, " ears and gives you a look of pure betrayal. \"I was in the middle of a very important sulk,\" ", <SUB, .type = 'subject>, " seems to say."},
    {<SUB, .type = 'actor, .capitalize = true>, " allows exactly two pets before pulling away with an offended sniff. \"That's quite enough of that,\" ", <SUB, .type = 'pos_adj>, " posture suggests."},
    {<SUB, .type = 'actor, .capitalize = true>, " tolerates the petting for precisely three seconds before ", <SUB, .type = 'pos_adj>, " tail starts twitching violently. \"Are you quite finished?\""},
    {<SUB, .type = 'actor, .capitalize = true>, " turns ", <SUB, .type = 'pos_adj>, " head away dramatically. \"I'm not some common housecat to be petted at your whim. I have standards, you know.\""},
    {<SUB, .type = 'actor, .capitalize = true>, " lets out a long-suffering sigh. \"Fine, if you must. But don't expect me to enjoy it.\""}
  };

  override import_export_id = "henri_pet_grouchy_msgs";
  override import_export_hierarchy = {"initial"};
endobject
