object HENRI_COMPLAINTS
  name: "Henri Complaints"
  parent: MSG_BAG
  owner: #2
  readable: true

  override entries = {
    {<SUB, .type = 'actor, .capitalize = true>, " notes, \"The dust gets everywhere. Absolutely everywhere.\""},
    {<SUB, .type = 'actor, .capitalize = true>, " complains, \"They moved my favorite sunbeam spot. The audacity.\""},
    {<SUB, .type = 'actor, .capitalize = true>, " grumbles, \"The hammering is giving me a headache. And I have very sensitive ears, you know.\""},
    {<SUB, .type = 'actor, .capitalize = true>, " sighs, \"This used to be a perfectly good nap spot before they started all this construction.\""},
    {<SUB, .type = 'actor, .capitalize = true>, " fusses, \"Do you know how hard it is to maintain this level of fur quality with all this sawdust floating around?\""},
    {<SUB, .type = 'actor, .capitalize = true>, " reminisces, \"My previous accommodations had much better acoustics for my midnight operas.\""},
    {<SUB, .type = 'actor, .capitalize = true>, " mutters, \"They keep moving the furniture. It's very disorienting for a creature of routine.\""}
  };

  override import_export_id = "henri_complaints";
endobject
