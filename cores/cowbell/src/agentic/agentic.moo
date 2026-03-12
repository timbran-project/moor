object AGENTIC
  name: "Agentic Objects"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  property agent (owner: ARCH_WIZARD, flags: "rc") = AGENTIC_AGENT;
  property coding_room (owner: ARCH_WIZARD, flags: "rc") = AGENTIC_CODING_ROOM;
  property event_queue (owner: ARCH_WIZARD, flags: "rc") = AGENTIC_EVENT_QUEUE;
  property loop (owner: ARCH_WIZARD, flags: "rc") = AGENTIC_LOOP;
  property room_observer (owner: ARCH_WIZARD, flags: "rc") = AGENTIC_ROOM_OBSERVER;
  property runner (owner: ARCH_WIZARD, flags: "rc") = AGENTIC_RUNNER;
  property tool (owner: ARCH_WIZARD, flags: "rc") = AGENTIC_TOOL;

  override description = "Namespace root for agentic components. Accessed as $agentic with subcomponents like $agentic.tool and $agentic.agent.";
  override import_export_hierarchy = {"agentic"};
  override import_export_id = "agentic";
endobject
