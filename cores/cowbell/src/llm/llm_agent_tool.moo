object LLM_AGENT_TOOL
  name: "LLM Agent Tool"
  parent: ROOT
  owner: HACKER
  fertile: true
  readable: true

  override description = "Flyweight delegate for LLM agent tool definitions. Converts to OpenAI tool schema and executes tool calls.";
  override import_export_hierarchy = {"llm"};
  override import_export_id = "llm_agent_tool";

  verb mk (this none this) owner: HACKER flags: "rxd"
    "Create a tool definition flyweight";
    {name, description, parameters, target_obj, target_verb} = args;
    typeof(name) == STR || raise(E_TYPE);
    typeof(description) == STR || raise(E_TYPE);
    typeof(parameters) == MAP || raise(E_TYPE);
    typeof(target_obj) == OBJ || raise(E_TYPE);
    typeof(target_verb) == STR || raise(E_TYPE);
    return <this, .name = name, .description = description, .parameters = parameters, .target_obj = target_obj, .target_verb = target_verb>;
  endverb

  verb to_schema (this none this) owner: HACKER flags: "rxd"
    "Convert tool definition to OpenAI tool schema format";
    return ["type" -> "function", "function" -> ["name" -> this.name, "description" -> this.description, "parameters" -> this.parameters]];
  endverb

  verb to_mcp_schema (this none this) owner: HACKER flags: "rxd"
    "Convert tool definition to MCP (Model Context Protocol) format for external agents";
    return ["name" -> this.name, "description" -> this.description, "input_schema" -> this.parameters, "target_obj" -> this.target_obj, "target_verb" -> this.target_verb];
  endverb

  verb execute (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Execute the tool with given arguments and optional actor";
    {args_json, ?actor = false} = args;
    "Parse arguments if they're JSON";
    if (typeof(args_json) == STR)
      tool_args = parse_json(args_json);
    else
      tool_args = args_json;
    endif
    "Dispatch to target verb with _tool_ prefix convention, passing {args, actor}";
    result = this.target_obj:(("_tool_" + this.target_verb))(tool_args, actor);
    return result;
  endverb
endobject