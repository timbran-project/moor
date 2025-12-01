object HENRI_KIBBLE_TAKEN_MSGS
  name: "Henri Kibble Taken Messages"
  parent: MSG_BAG
  owner: #2
  readable: true

  override entries = {
    {<SUB, .capitalize = true, .type = 'actor>, " starts weaving around ", <SUB, .capitalize = false, .type = 'dobj_pos_adj>, " legs, purring loudly."},
    {<SUB, .capitalize = true, .type = 'actor>, " perks up immediately, tail suddenly upright and alert. The sulking can wait."},
    {<SUB, .capitalize = true, .type = 'actor>, " trots over with uncharacteristic enthusiasm. \"Well, finally some proper service.\""},
    {<SUB, .capitalize = true, .type = 'actor>, " abandons ", <SUB, .capitalize = false, .type = 'pos_adj>, " aloof demeanor entirely, eyes locked on the kibble."},
    {<SUB, .capitalize = true, .type = 'actor>, " forgets to be grouchy for a moment, whiskers twitching with anticipation."}
  };

  override import_export_id = "henri_kibble_taken_msgs";
  override import_export_hierarchy = {"initial"};
endobject
