object HOUSEKEEPING_SWEEP_MSGS
  name: "Housekeeping Sweep Messages"
  parent: MSG_BAG
  owner: ARCH_WIZARD

  override entries = {
    {
      "A member of housekeeping gently guides ",
      <#19, .type = 'actor, .capitalize = false>,
      " back to bed."
    },
    {
      "Housekeeping escorts ",
      <#19, .type = 'actor, .capitalize = false>,
      " away to ",
      <#19, .type = 'pos_adj, .capitalize = false>,
      " room."
    },
    {
      <#19, .type = 'actor, .capitalize = true>,
      " is quietly led away by a tired-looking porter."
    },
    {
      "A woman with a broom nudges ",
      <#19, .type = 'actor, .capitalize = false>,
      " awake and points toward the back stairs."
    },
    {
      <#19, .type = 'actor, .capitalize = true>,
      " is gently but firmly ushered toward the dormitory."
    }
  };
  override import_export_hierarchy = {"initial"};
  override import_export_id = "housekeeping_sweep_msgs";
endobject