object LLM_RESPONSE
  name: "LLM Response"
  parent: ROOT
  owner: ARCH_WIZARD

  override import_export_hierarchy = {"llm"};
  override import_export_id = "llm_response";

  verb mk (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Create a flyweight wrapping an LLM API response map.";
    {response_map} = args;
    return toflyweight(this, ['raw -> response_map]);
  endverb

  verb is_valid (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Check if response has valid structure with choices.";
    raw = this.raw;
    typeof(raw) != TYPE_MAP && return false;
    !maphaskey(raw, "choices") && return false;
    typeof(raw["choices"]) != TYPE_LIST && return false;
    return length(raw["choices"]) > 0;
  endverb

  verb message (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Get the first choice's message, sanitized for API re-submission.";
    !this:is_valid() && return [];
    msg = this.raw["choices"][1]["message"];
    "Sanitize: remove fields that are the string 'null' or invalid";
    cleaned = ["role" -> msg["role"] || "assistant"];
    "Only include content if it's a real string (not 'null')";
    content = msg["content"];
    if (typeof(content) == TYPE_STR && content != "null")
      "Strip leading 'null' garbage some models produce";
      while (length(content) > 4 && content[1..4] == "null")
        content = content[5..length(content)];
        "Also strip leading whitespace/newlines";
        while (length(content) > 0 && (content[1] == " " || content[1] == "\n"))
          content = content[2..length(content)];
        endwhile
      endwhile
      length(content) > 0 && (cleaned["content"] = content);
    endif
    "Only include tool_calls if it's a real list";
    tc = msg["tool_calls"];
    if (typeof(tc) == TYPE_LIST && length(tc) > 0)
      cleaned["tool_calls"] = tc;
    endif
    "Don't include name, reasoning_content, or other junk fields";
    return cleaned;
  endverb

  verb content (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Extract content from response, handling both content and reasoning_content.";
    msg = this:message();
    typeof(msg) != TYPE_MAP && return "";
    maphaskey(msg, "content") && typeof(msg["content"]) == TYPE_STR && msg["content"] != "" && msg["content"] != "null" && return msg["content"];
    maphaskey(msg, "reasoning_content") && typeof(msg["reasoning_content"]) == TYPE_STR && msg["reasoning_content"] != "null" && return msg["reasoning_content"];
    return "";
  endverb

  verb tool_calls (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Get tool_calls list from message, or empty list if none.";
    msg = this:message();
    typeof(msg) != TYPE_MAP && return {};
    !maphaskey(msg, "tool_calls") && return {};
    tc = msg["tool_calls"];
    typeof(tc) != TYPE_LIST && return {};
    return tc;
  endverb

  verb has_tool_calls (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Check if response has any tool calls.";
    return length(this:tool_calls()) > 0;
  endverb

  verb usage (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Get usage stats map, or empty map if not present.";
    raw = this.raw;
    typeof(raw) != TYPE_MAP && return [];
    !maphaskey(raw, "usage") && return [];
    return raw["usage"];
  endverb

  verb test_flyweight (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Test $llm_response flyweight methods.";
    "Test valid response with content";
    sample = ["choices" -> {["message" -> ["content" -> "Hello!"]]}];
    resp = this:mk(sample);
    resp:is_valid() || raise(E_ASSERT, "should be valid");
    resp:content() != "Hello!" && raise(E_ASSERT, "content should be Hello!");
    resp:has_tool_calls() && raise(E_ASSERT, "should have no tool calls");
    length(resp:tool_calls()) != 0 && raise(E_ASSERT, "tool_calls should be empty");
    "Test response with tool calls";
    sample2 = ["choices" -> {["message" -> ["content" -> "", "tool_calls" -> {["id" -> "1", "function" -> ["name" -> "test", "arguments" -> []]]}]]}, "usage" -> ["total_tokens" -> 100]];
    resp2 = this:mk(sample2);
    (resp2):is_valid() || raise(E_ASSERT, "should be valid with tools");
    !(resp2):has_tool_calls() && raise(E_ASSERT, "should have tool calls");
    length((resp2):tool_calls()) != 1 && raise(E_ASSERT, "should have 1 tool call");
    (resp2):usage()["total_tokens"] != 100 && raise(E_ASSERT, "usage should have total_tokens");
    "Test reasoning_content fallback";
    sample3 = ["choices" -> {["message" -> ["reasoning_content" -> "Thinking..."]]}];
    resp3 = this:mk(sample3);
    (resp3):content() != "Thinking..." && raise(E_ASSERT, "should fall back to reasoning_content");
    "Test invalid responses";
    resp4 = this:mk("not a map");
    (resp4):is_valid() && raise(E_ASSERT, "string should be invalid");
    resp5 = this:mk(["no_choices" -> 1]);
    (resp5):is_valid() && raise(E_ASSERT, "missing choices should be invalid");
    resp6 = this:mk(["choices" -> {}]);
    (resp6):is_valid() && raise(E_ASSERT, "empty choices should be invalid");
    return true;
  endverb

  verb reasoning (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Extract reasoning_content from response.";
    msg = this:message();
    typeof(msg) != TYPE_MAP && return "";
    maphaskey(msg, "reasoning_content") && typeof(msg["reasoning_content"]) == TYPE_STR && msg["reasoning_content"] != "null" && return msg["reasoning_content"];
    return "";
  endverb
endobject