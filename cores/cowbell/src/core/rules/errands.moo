object ERRANDS [
  import_export_id -> "errands",
  import_export_hierarchy -> {"rules"}
]
  name: "Errands"
  parent: PLAYBOOK
  owner: ARCH_WIZARD
  readable: true

  override description (owner: HACKER, flags: "rc") = "Walking to places and fetching things, for any owned NPC.";
  override goals (owner: ARCH_WIZARD, flags: "rc") = [
    'go_to -> ['description -> "Walk to a room through open exits.", 'inputs -> ['place -> 'object]],
    'open_up -> ['description -> "Make sure a container is open.", 'inputs -> ['box -> 'object]],
    'fetch -> ['description -> "Bring an item to a room.", 'inputs -> ['item -> 'object, 'to -> 'object]]
  ];
  override approaches (owner: ARCH_WIZARD, flags: "rc") = {
    ['goal -> 'go_to, 'name -> 'here, 'requires -> "location_is(object: input.actor, location: input.place)", 'steps -> {}],
    ['goal -> 'go_to, 'name -> 'walk, 'requires -> "location_of(object: input.actor) -> (location: Here) AND next_step(from: binding.Here, to: input.place) -> (exit: Exit)", 'steps -> {{'action, 'go, ['target -> "binding.Here", 'exit -> "binding.Exit"]}, {'goal, 'go_to, ['place -> "input.place"]}}],
    ['goal -> 'open_up, 'name -> 'already_open, 'requires -> "is_open(object: input.box)", 'steps -> {}],
    ['goal -> 'open_up, 'name -> 'open_it, 'requires -> "", 'steps -> {{'action, 'open, ['target -> "input.box"]}}],
    ['goal -> 'fetch, 'name -> 'delivered, 'requires -> "location_is(object: input.item, location: input.to)", 'steps -> {}],
    ['goal -> 'fetch, 'name -> 'carrying, 'requires -> "location_is(object: input.item, location: input.actor)", 'steps -> {{'goal, 'go_to, ['place -> "input.to"]}, {'action, 'drop, ['target -> "input.item"]}}],
    ['goal -> 'fetch, 'name -> 'from_container, 'requires -> "location_of(object: input.item) -> (location: Box) AND isa(object: binding.Box, prototype: parameter.container) AND location_of(object: binding.Box) -> (location: Room)", 'steps -> {{'goal, 'go_to, ['place -> "binding.Room"]}, {'goal, 'open_up, ['box -> "binding.Box"]}, {'action, 'take_from, ['target -> "binding.Box", 'item -> "input.item"]}, {'goal, 'go_to, ['place -> "input.to"]}, {'action, 'drop, ['target -> "input.item"]}}],
    ['goal -> 'fetch, 'name -> 'carry, 'requires -> "location_of(object: input.item) -> (location: Where)", 'steps -> {{'goal, 'go_to, ['place -> "binding.Where"]}, {'action, 'get, ['target -> "input.item"]}, {'goal, 'go_to, ['place -> "input.to"]}, {'action, 'drop, ['target -> "input.item"]}}]
  };
  override settings (owner: ARCH_WIZARD, flags: "rc") = ['container -> CONTAINER];
endobject
