object HENRI_COMPLAINTS
  name: "Henri Complaints"
  parent: MSG_BAG
  owner: ARCH_WIZARD
  readable: true

  override entries = {
    {
      <#19, .capitalize = true, .type = 'actor>,
      " notes, \"The dust gets everywhere. Absolutely everywhere.\""
    },
    {
      <#19, .capitalize = true, .type = 'actor>,
      " complains, \"They moved my favorite sunbeam spot. The audacity.\""
    },
    {
      <#19, .capitalize = true, .type = 'actor>,
      " grumbles, \"The hammering is giving me a headache. And I have very sensitive ears, you know.\""
    },
    {
      <#19, .capitalize = true, .type = 'actor>,
      " sighs, \"This used to be a perfectly good nap spot before they started all this construction.\""
    },
    {
      <#19, .capitalize = true, .type = 'actor>,
      " fusses, \"Do you know how hard it is to maintain this level of fur quality with all this sawdust floating around?\""
    },
    {
      <#19, .capitalize = true, .type = 'actor>,
      " reminisces, \"My previous accommodations had much better acoustics for my midnight operas.\""
    },
    {
      <#19, .capitalize = true, .type = 'actor>,
      " mutters, \"They keep moving the furniture. It's very disorienting for a creature of routine.\""
    }
  };
  override import_export_hierarchy = {"initial"};
  override import_export_id = "henri_complaints";
endobject
