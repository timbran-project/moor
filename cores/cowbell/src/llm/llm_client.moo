object LLM_CLIENT
  name: "LLM Client"
  parent: ROOT
  owner: HACKER
  readable: true

  property api_endpoint (owner: HACKER, flags: "r") = 0;
  property api_key (owner: ARCH_WIZARD, flags: "") = 0;
  property model (owner: HACKER, flags: "r") = "GLM-4.6";

  override description = "OpenAI-compatible LLM API client for chat completions using worker_request.";
  override import_export_hierarchy = {"llm"};
  override import_export_id = "llm_client";

  verb chat (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Make a chat completion request to LLM API";
    "Args: input (string or messages list), opts (optional $llm_chat_opts flyweight),";
    "      model_override, stream, tools";
    {input, ?opts = false, ?model_override = false, ?stream = false, ?tools = false} = args;
    this.api_key || raise(E_PERM, "LLM API key not configured");
    messages = typeof(input) == TYPE_STR ? {["role" -> "user", "content" -> input]} | (typeof(input) == TYPE_LIST ? input | raise(E_TYPE));
    model = model_override || this.model;
    body = ["model" -> model, "messages" -> messages, "stream" -> stream];
    tools && (body["tools"] = tools);
    if (typeof(opts) == TYPE_FLYWEIGHT)
      for key in (mapkeys(opts_params = opts:to_body_params()))
        body[key] = opts_params[key];
      endfor
    endif
    headers = {{"Content-Type", "application/json"}, {"Authorization", "Bearer " + this.api_key}};
    req_start = ftime();
    response = worker_request('curl, {"POST", this.api_endpoint, generate_json(body), headers});
    req_end = ftime();
    typeof(response) == TYPE_LIST && length(response) >= 3 || raise(E_INVARG, "Invalid response from LLM: " + toliteral(response));
    {status, response_headers, body} = response;
    server_log("LLM response " + tostr(status) + " time: " + tostr(req_end - req_start) + "s (" + model + " @ " + this.api_endpoint + ")");
    if (status < 200 || status >= 300)
      err = status == 401 || status == 403 ? E_PERM | E_INVARG;
      raise(err, "LLM API error: HTTP " + tostr(status) + " - " + body);
    endif
    typeof(body) == TYPE_STR || return body;
    body != "" || raise(E_INVARG, "LLM API returned empty response");
    return parse_json(body);
  endverb

  verb set_api_key (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Set the LLM API key. Permission: wizard, owner, or 'set_api_key capability.";
    {this, perms} = this:check_permissions('set_api_key);
    set_task_perms(perms);
    {new_key} = args;
    typeof(new_key) == TYPE_STR || raise(E_TYPE);
    this.api_key = new_key;
  endverb

  verb simple_query (this none this) owner: HACKER flags: "rxd"
    "Convenience method for simple string queries, returns just the message content";
    {query} = args;
    response = this:chat(query);
    if (typeof(response) == TYPE_MAP && maphaskey(response, "choices") && length(response["choices"]) > 0)
      choice = response["choices"][1];
      if (maphaskey(choice, "message") && maphaskey(choice["message"], "content"))
        return choice["message"]["content"];
      endif
    endif
    return response;
  endverb

  verb is_configured (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Check if the LLM client has an API key configured";
    return this.api_key && typeof(this.api_key) == TYPE_STR && length(this.api_key) > 0;
  endverb
endobject
