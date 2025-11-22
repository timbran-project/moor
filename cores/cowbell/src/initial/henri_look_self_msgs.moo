object HENRI_LOOK_SELF_MSGS
  name: "Henri Look-Self Messages"
  parent: MSG_BAG
  owner: HACKER
  readable: true

  override entries = {
    {<SUB, .type = 'actor, .capitalize = true>, " glares at you with an expression that clearly says 'This is all your fault, isn't it?' Their tail twitches irritably."},
    {<SUB, .type = 'actor, .capitalize = true>, " is trying to nap despite the construction noise, but keeps getting interrupted. You can see the sleep-deprived annoyance in their half-closed eyes."},
    {<SUB, .type = 'actor, .capitalize = true>, " seems mildly interested in something despite the general annoyance. Probably wondering if you brought treats or if you're just another source of disappointment."},
    {<SUB, .type = 'actor, .capitalize = true>, " gives you a look that manages to convey both disdain and resignation about their current living conditions."}
  };

  override import_export_id = "henri_look_self_msgs";
endobject
