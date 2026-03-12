object AGENTIC_ROOM_OBSERVER
  name: "Agentic Room Observer"
  parent: ARCH_WIZARD
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  property agent (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property enabled (owner: ARCH_WIZARD, flags: "rc") = 1;
  property runner (owner: ARCH_WIZARD, flags: "rc") = #-1;

  override description = "Room-facing observer adapter built on the agentic runtime.";
  override import_export_hierarchy = {"agentic"};
  override import_export_id = "agentic_room_observer";

  verb configure (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Create a fresh agent and runner for this observer.";
    caller == this || caller == this.owner || caller_perms().wizard || raise(E_PERM);
    this.agent = $agentic.agent:create(true);
    this.agent.owner = this.owner;
    this.agent.token_owner = this;
    this.runner = create($agentic.runner, this.owner);
    this.runner:attach_agent(this.agent);
    return this.agent;
  endverb

  verb respond_once (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Run one response pass for a prompt and optionally announce speech.";
    this.enabled || return "Observer disabled.";
    valid(this.runner) || this:configure();
    {prompt, ?announce = 0} = args;
    response = this.runner:run_once(prompt);
    if (announce && typeof(response) == TYPE_STR && valid(this.location) && length(response) > 0)
      this.location:announce($event:mk_say(this, this:name(), " says, \"", response, "\""));
    endif
    return response;
  endverb

  verb observer_status (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return a compact observer diagnostics map.";
    return ["enabled" -> this.enabled, "agent" -> this.agent, "runner" -> this.runner, "agent_valid" -> valid(this.agent), "runner_valid" -> valid(this.runner)];
  endverb
endobject