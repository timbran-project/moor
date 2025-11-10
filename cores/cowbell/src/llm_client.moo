object LLM_CLIENT
  name: "LLM Client"
  parent: ROOT
  owner: HACKER
  readable: true

  property api_endpoint (owner: HACKER, flags: "rc") = "https://api.deepseek.com/chat/completions";
  property api_key (owner: ARCH_WIZARD, flags: "") = 0;
  property model (owner: HACKER, flags: "rc") = "deepseek-chat";

  override description = "OpenAI-compatible LLM API client for chat completions using worker_request.";
  override import_export_id = "llm_client";

  verb chat (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Make a chat completion request to LLM API";
    "Args: either a string message or a messages list {[\"role\" -> \"user\", \"content\" -> \"...\"]};";
    {input, ?model_override = false, ?stream = false, ?tools = false} = args;
    if (!this.api_key)
      raise(E_INVARG("LLM API key not configured"));
    endif
    "Convert input to messages array if it's a string";
    if (typeof(input) == STR)
      messages = {["role" -> "user", "content" -> input]};
    elseif (typeof(input) == LIST)
      messages = input;
    else
      raise(E_TYPE);
    endif
    model = model_override || this.model;
    "Construct the request body";
    body = ["model" -> model, "messages" -> messages, "stream" -> stream];
    if (tools)
      body["tools"] = tools;
    endif
    body_json = generate_json(body);
    "Construct headers with API key";
    headers = {{"Content-Type", "application/json"}, {"Authorization", "Bearer " + this.api_key}};
    "Make the worker request";
    response = worker_request('curl, {"POST", this.api_endpoint, body_json, headers});
    "Parse and return the response";
    "worker_request returns {status_code, headers, body_string}";
    if (typeof(response) == LIST && length(response) >= 3)
      {status, response_headers, body} = response;
      "Check for HTTP errors";
      if (status < 200 || status >= 300)
        raise(E_INVARG("LLM API error: HTTP " + tostr(status) + " - " + body));
      endif
      if (typeof(body) == STR)
        "Don't try to parse empty responses";
        if (body == "")
          raise(E_INVARG("LLM API returned empty response"));
        endif
        parsed = parse_json(body);
        return parsed;
      endif
      return body;
    elseif (typeof(response) == STR)
      if (response == "")
        raise(E_INVARG("LLM API returned empty response"));
      endif
      parsed = parse_json(response);
      return parsed;
    endif
    return response;
  endverb

  verb set_api_key (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Set the LLM API key. Permission: wizard, owner, or 'set_api_key capability.";
    {this, perms} = this:check_permissions('set_api_key);
    set_task_perms(perms);
    {new_key} = args;
    typeof(new_key) == STR || raise(E_TYPE);
    this.api_key = new_key;
  endverb

  verb simple_query (this none this) owner: HACKER flags: "rxd"
    "Convenience method for simple string queries, returns just the message content";
    {query} = args;
    response = this:chat(query);
    if (typeof(response) == MAP && maphaskey(response, "choices") && length(response["choices"]) > 0)
      choice = response["choices"][1];
      if (maphaskey(choice, "message") && maphaskey(choice["message"], "content"))
        return choice["message"]["content"];
      endif
    endif
    return response;
  endverb
endobject