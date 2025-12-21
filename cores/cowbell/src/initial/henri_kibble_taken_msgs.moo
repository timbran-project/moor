object HENRI_KIBBLE_TAKEN_MSGS
  name: "Henri Kibble Taken Messages"
  parent: MSG_BAG
  owner: ARCH_WIZARD
  readable: true

  override entries = {
    {
      <#19, .type = 'actor, .capitalize = true>,
      " starts weaving around ",
      <#19, .type = 'dobj_pos_adj, .capitalize = false>,
      " legs, purring loudly."
    },
    {
      <#19, .type = 'actor, .capitalize = true>,
      " perks up immediately, tail suddenly upright and alert. The sulking can wait."
    },
    {
      <#19, .type = 'actor, .capitalize = true>,
      " trots over with uncharacteristic enthusiasm. \"Well, finally some proper service.\""
    },
    {
      <#19, .type = 'actor, .capitalize = true>,
      " abandons ",
      <#19, .type = 'pos_adj, .capitalize = false>,
      " aloof demeanor entirely, eyes locked on the kibble."
    },
    {
      <#19, .type = 'actor, .capitalize = true>,
      " forgets to be grouchy for a moment, whiskers twitching with anticipation."
    }
  };
  override import_export_hierarchy = {"initial"};
  override import_export_id = "henri_kibble_taken_msgs";
endobject