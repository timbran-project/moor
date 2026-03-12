object AGENTIC_LOOP
  name: "Agentic Loop Delegate"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  override description = "Flyweight delegate for the agentic loop turn processor.";
  override import_export_hierarchy = {"agentic"};
  override import_export_id = "agentic_loop";

  verb run_turn (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Run one agent turn: call LLM, execute tools, append context, and return status map.";
    {agent, ?opts = false} = args;
    typeof(agent) == TYPE_OBJ && valid(agent) || raise(E_INVARG, "agent must be a valid object");
    response = agent:_call_llm_with_retry(agent:_get_tool_schemas(), opts);
    agent:_track_token_usage(response);
    if (!response:is_valid())
      return ["status" -> "invalid", "raw" -> response.raw];
    endif
    if (!response:has_tool_calls())
      content = response:content();
      agent:add_message("assistant", content);
      return ["status" -> "complete", "content" -> content];
    endif
    tool_results = {};
    all_failed = true;
    for tool_call in (response:tool_calls())
      result = agent:_execute_tool_call(tool_call);
      tool_results = {@tool_results, result};
      tc_content = `result["content"] ! ANY => ""';
      if (!(typeof(tc_content) == TYPE_STR && (tc_content:starts_with("TOOL BLOCKED:") || tc_content:starts_with("ERROR:"))))
        all_failed = false;
      endif
    endfor
    agent.context = {@agent.context, response:message(), @tool_results};
    if (all_failed && length(tool_results) > 0)
      return ["status" -> "all_failed", "tool_results" -> tool_results];
    endif
    return ["status" -> "tool_calls", "tool_results" -> tool_results];
  endverb
endobject
