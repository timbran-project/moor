object AGENTIC_RUNNER
  name: "Agentic Runner"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  property agent (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property enabled (owner: ARCH_WIZARD, flags: "rc") = 1;

  override description = "Runtime adapter that binds an agent to an event source/sink.";
  override import_export_hierarchy = {"agentic"};
  override import_export_id = "agentic_runner";

  verb attach_agent (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Attach a specific agent instance to this runner.";
    {agent_obj} = args;
    typeof(agent_obj) == TYPE_OBJ && valid(agent_obj) || raise(E_INVARG, "agent_obj must be valid object");
    this.agent = agent_obj;
    return this.agent;
  endverb

  verb run_once (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Run one prompt through attached agent.";
    this.enabled || return "Runner disabled.";
    valid(this.agent) || raise(E_INVARG, "No agent attached");
    {prompt, ?opts = false} = args;
    return this.agent:send_message(prompt, opts);
  endverb

  verb status (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return runner status map.";
    return ["enabled" -> this.enabled, "agent" -> this.agent, "agent_valid" -> valid(this.agent)];
  endverb
endobject