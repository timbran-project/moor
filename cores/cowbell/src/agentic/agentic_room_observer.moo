object AGENTIC_ROOM_OBSERVER [
  import_export_id -> "agentic_room_observer",
  import_export_hierarchy -> {"agentic"}
]
  name: "Agentic Room Observer"
  parent: ARCH_WIZARD
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  property agent (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property enabled (owner: ARCH_WIZARD, flags: "rc") = 1;
  property runner (owner: ARCH_WIZARD, flags: "rc") = #-1;

  override description (owner: ARCH_WIZARD, flags: "rc") = "Room-facing observer adapter built on the agentic runtime.";

  method configure owner: ARCH_WIZARD
    "Create a fresh agent and runner for this observer.";
    const principal = caller_perms();
    principal == this.owner || principal.wizard || raise(E_PERM);
    caller == this || caller == this.owner || caller_perms().wizard || raise(E_PERM);
    this.agent = $agentic.agent:create(true);
    this.agent.owner = this.owner;
    this.agent.token_owner = this;
    this.runner = create($agentic.runner, this.owner);
    this.runner:attach_agent(this.agent);
    return this.agent;
  endmethod

  method respond_once owner: ARCH_WIZARD
    "Run one response pass for a prompt and optionally announce speech.";
    const principal = caller_perms();
    principal == this.owner || principal.wizard || raise(E_PERM);
    this.enabled || return "Observer disabled.";
    valid(this.runner) || this:configure();
    const {prompt, ?announce = 0} = args;
    const response = this.runner:run_once(prompt, false, principal);
    if (announce && typeof(response) == TYPE_STR && valid(this.location) && length(response) > 0)
      this.location:announce($event:mk_say(this, this:name(), " says, \"", response, "\""));
    endif
    return response;
  endmethod

  method observer_status owner: ARCH_WIZARD
    "Return a compact observer diagnostics map.";
    const principal = caller_perms();
    principal == this.owner || principal.wizard || raise(E_PERM);
    return ["enabled" -> this.enabled, "agent" -> this.agent, "runner" -> this.runner, "agent_valid" -> valid(this.agent), "runner_valid" -> valid(this.runner)];
  endmethod
endobject
