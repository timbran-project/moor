object HENRI_KIBBLE_TAKEN_MSGS
  name: "Henri Kibble Taken Messages"
  parent: MSG_BAG
  owner: ARCH_WIZARD
  readable: true

  override entries = {
    {
      <#19, .capitalize = true, .type = 'actor>,
      " starts weaving around ",
      <#19, .capitalize = false, .type = 'dobj_pos_adj>,
      " legs, purring loudly."
    },
    {
      <#19, .capitalize = true, .type = 'actor>,
      " perks up immediately, tail suddenly upright and alert. The sulking can wait."
    },
    {
      <#19, .capitalize = true, .type = 'actor>,
      " trots over with uncharacteristic enthusiasm. \"Well, finally some proper service.\""
    },
    {
      <#19, .capitalize = true, .type = 'actor>,
      " abandons ",
      <#19, .capitalize = false, .type = 'pos_adj>,
      " aloof demeanor entirely, eyes locked on the kibble."
    },
    {
      <#19, .capitalize = true, .type = 'actor>,
      " forgets to be grouchy for a moment, whiskers twitching with anticipation."
    }
  };
  override import_export_hierarchy = {"initial"};
  override import_export_id = "henri_kibble_taken_msgs";
endobject
