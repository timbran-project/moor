object HOUSEKEEPING_SWEEP_MSGS
  name: "Housekeeping Sweep Messages"
  parent: MSG_BAG
  owner: ARCH_WIZARD

  override entries = {
    {
      "A member of housekeeping gently guides ",
      <#19, .capitalize = false, .type = 'actor>,
      " back to bed."
    },
    {
      "Housekeeping escorts ",
      <#19, .capitalize = false, .type = 'actor>,
      " away to ",
      <#19, .capitalize = false, .type = 'pos_adj>,
      " room."
    },
    {
      <#19, .capitalize = true, .type = 'actor>,
      " is quietly led away by a tired-looking porter."
    },
    {
      "A woman with a broom nudges ",
      <#19, .capitalize = false, .type = 'actor>,
      " awake and points toward the back stairs."
    },
    {
      <#19, .capitalize = true, .type = 'actor>,
      " is gently but firmly ushered toward the dormitory."
    }
  };
  override import_export_hierarchy = {"initial"};
  override import_export_id = "housekeeping_sweep_msgs";
endobject
