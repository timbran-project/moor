object LLM_CHAT_OPTS
  name: "LLM Chat Options"
  parent: ROOT
  owner: HACKER
  fertile: true
  readable: true

  override description = "Flyweight delegate for LLM chat request options. Builder pattern: $llm_chat_opts:mk():with_temperature(0.3):with_tool_choice('required)";
  override import_export_hierarchy = {"llm"};
  override import_export_id = "llm_chat_opts";

  verb mk (this none this) owner: HACKER flags: "rxd"
    "Create an empty chat options flyweight";
    return <this>;
  endverb

  verb with_temperature (this none this) owner: HACKER flags: "rxd"
    "Set sampling temperature (0-2, lower = more deterministic)";
    {temp} = args;
    typeof(temp) in {INT, FLOAT} || raise(E_TYPE, "temperature must be a number");
    slots = flyslots(this);
    slots['temperature] = temp;
    return toflyweight(this.delegate, slots);
  endverb

  verb with_max_tokens (this none this) owner: HACKER flags: "rxd"
    "Set maximum output tokens";
    {max} = args;
    typeof(max) == INT || raise(E_TYPE, "max_tokens must be an integer");
    slots = flyslots(this);
    slots['max_tokens] = max;
    return toflyweight(this.delegate, slots);
  endverb

  verb with_tool_choice (this none this) owner: HACKER flags: "rxd"
    "Set tool choice: 'auto, 'none, 'required, or ['type -> 'function, 'function -> ['name -> \"fn\"]]";
    {choice} = args;
    slots = flyslots(this);
    slots['tool_choice] = choice;
    return toflyweight(this.delegate, slots);
  endverb

  verb with_top_p (this none this) owner: HACKER flags: "rxd"
    "Set nucleus sampling threshold (0-1)";
    {p} = args;
    typeof(p) in {INT, FLOAT} || raise(E_TYPE, "top_p must be a number");
    slots = flyslots(this);
    slots['top_p] = p;
    return toflyweight(this.delegate, slots);
  endverb

  verb with_frequency_penalty (this none this) owner: HACKER flags: "rxd"
    "Set frequency penalty (-2 to 2, penalizes repeated tokens)";
    {penalty} = args;
    typeof(penalty) in {INT, FLOAT} || raise(E_TYPE, "frequency_penalty must be a number");
    slots = flyslots(this);
    slots['frequency_penalty] = penalty;
    return toflyweight(this.delegate, slots);
  endverb

  verb with_presence_penalty (this none this) owner: HACKER flags: "rxd"
    "Set presence penalty (-2 to 2, encourages new topics)";
    {penalty} = args;
    typeof(penalty) in {INT, FLOAT} || raise(E_TYPE, "presence_penalty must be a number");
    slots = flyslots(this);
    slots['presence_penalty] = penalty;
    return toflyweight(this.delegate, slots);
  endverb

  verb with_stop (this none this) owner: HACKER flags: "rxd"
    "Set stop sequences (string or list of strings)";
    {stop} = args;
    slots = flyslots(this);
    slots['stop] = stop;
    return toflyweight(this.delegate, slots);
  endverb

  verb with_json_mode (this none this) owner: HACKER flags: "rxd"
    "Enable JSON output mode";
    slots = flyslots(this);
    slots['response_format] = ["type" -> "json_object"];
    return toflyweight(this.delegate, slots);
  endverb

  verb to_body_params (this none this) owner: HACKER flags: "rxd"
    "Extract API parameters from flyweight slots, converting symbols to strings for JSON";
    result = [];
    slots = flyslots(this);
    for key in (mapkeys(slots))
      val = slots[key];
      "Convert symbol tool_choice value to string for API";
      if (key == 'tool_choice && typeof(val) == SYM)
        val = tostr(val);
      endif
      "Use string key for JSON compatibility";
      result[tostr(key)] = val;
    endfor
    return result;
  endverb
endobject