object AGENTIC_TOOL [
  import_export_id -> "agentic_tool",
  import_export_hierarchy -> {"agentic"}
]
  name: "Agentic Tool Delegate"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  override description = "Flyweight delegate for agentic tool definitions and execution.";

  method mk owner: ARCH_WIZARD
    "Create an agentic tool definition flyweight.";
    {name, description, parameters, target_obj, target_verb} = args;
    typeof(name) == TYPE_STR || raise(E_TYPE, "name must be string");
    typeof(description) == TYPE_STR || raise(E_TYPE, "description must be string");
    typeof(parameters) == TYPE_MAP || raise(E_TYPE, "parameters must be map");
    typeof(target_obj) == TYPE_OBJ || raise(E_TYPE, "target_obj must be object");
    typeof(target_verb) == TYPE_STR || raise(E_TYPE, "target_verb must be string");
    return <this, .name = name, .description = description, .parameters = parameters, .target_obj = target_obj, .target_verb = target_verb>;
  endmethod

  method to_schema owner: ARCH_WIZARD
    "Convert tool definition to OpenAI function tool schema.";
    return ["type" -> "function", "function" -> ["name" -> this.name, "description" -> this.description, "parameters" -> this.parameters]];
  endmethod

  method to_mcp_schema owner: ARCH_WIZARD
    "Convert tool definition to MCP-style schema.";
    return ["name" -> this.name, "description" -> this.description, "input_schema" -> this.parameters, "target_obj" -> this.target_obj, "target_verb" -> this.target_verb];
  endmethod

  method execute owner: ARCH_WIZARD
    "Execute tool with args map (or JSON string) and optional actor.";
    isa(caller, $agentic_agent) || raise(E_PERM);
    {args_json, ?actor = #-1} = args;
    if (typeof(args_json) == TYPE_STR)
      tool_args = parse_json(args_json);
    else
      tool_args = args_json;
    endif
    prefixed_verb = "_tool_" + this.target_verb;
    if (respond_to(this.target_obj, prefixed_verb))
      return this.target_obj:(prefixed_verb)(tool_args, actor);
    elseif (respond_to(this.target_obj, this.target_verb))
      return this.target_obj:(this.target_verb)(tool_args, actor);
    endif
    raise(E_VERBNF, "Tool handler not found: " + prefixed_verb + " or " + this.target_verb);
  endmethod
endobject
