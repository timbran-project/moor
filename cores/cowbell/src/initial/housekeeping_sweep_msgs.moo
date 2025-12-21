object HOUSEKEEPING_SWEEP_MSGS
  name: "Housekeeping Sweep Messages"
  parent: MSG_BAG
  owner: ARCH_WIZARD

  override entries = {
    {
      "A member of housekeeping gently guides ",
      <SUB, .capitalize = false, .type = 'actor>,
      " back to bed."
    },
    {
      "Housekeeping escorts ",
      <SUB, .capitalize = false, .type = 'actor>,
      " away to ",
      <SUB, .capitalize = false, .type = 'pos_adj>,
      " room."
    },
    {
      <SUB, .capitalize = true, .type = 'actor>,
      " is quietly led away by a tired-looking porter."
    },
    {
      "A woman with a broom nudges ",
      <SUB, .capitalize = false, .type = 'actor>,
      " awake and points toward the back stairs."
    },
    {
      <SUB, .capitalize = true, .type = 'actor>,
      " is gently but firmly ushered toward the dormitory."
    }
  };
  override import_export_hierarchy = {"initial"};
  override import_export_id = "housekeeping_sweep_msgs";
endobject