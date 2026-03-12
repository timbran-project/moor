object LLM_CLIENT
  name: "LLM Client"
  parent: ROOT
  owner: HACKER
  readable: true

  property api_endpoint (owner: HACKER, flags: "r") = 0;
  property api_key (owner: ARCH_WIZARD, flags: "") = 0;
  property model (owner: HACKER, flags: "r") = 0;

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
        content = choice["message"]["content"];
        if (typeof(content) == TYPE_STR)
          cleaned = content:trim();
          lbrace = index(cleaned, "{");
          rbrace = rindex(cleaned, "}");
          if (lbrace && rbrace && rbrace >= lbrace)
            candidate = cleaned[lbrace..rbrace];
            if (`parse_json(candidate) ! ANY => false')
              return candidate;
            endif
          endif
          if (`parse_json(cleaned) ! ANY => false')
            return cleaned;
          endif
        endif
        return content;
      endif
    endif
    return response;
  endverb

  verb is_configured (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Check if the LLM client has an API key configured";
    return this.api_key && typeof(this.api_key) == TYPE_STR && length(this.api_key) > 0;
  endverb

  verb list_models (this none this) owner: ARCH_WIZARD flags: "rxd"
    "List available models from the provider's /models endpoint.";
    "Returns normalized output by default. Pass \"raw\" as first arg for provider-native payload.";
    mode = "normalized";
    limit = 0;
    if (length(args) >= 1)
      if (typeof(args[1]) == TYPE_STR)
        mode = args[1]:trim():lowercase();
      elseif (typeof(args[1]) == TYPE_INT)
        limit = args[1];
      endif
    endif
    if (length(args) >= 2 && typeof(args[2]) == TYPE_INT)
      limit = args[2];
    endif
    this.api_endpoint || raise(E_INVARG, "LLM API endpoint not configured");
    endpoint = this.api_endpoint;
    models_endpoint = endpoint;
    if (models_endpoint:ends_with("/chat/completions"))
      models_endpoint = models_endpoint[1..length(models_endpoint) - 17] + "/models";
    elseif (models_endpoint:ends_with("/completions"))
      models_endpoint = models_endpoint[1..length(models_endpoint) - 12] + "/models";
    elseif (models_endpoint:ends_with("/responses"))
      models_endpoint = models_endpoint[1..length(models_endpoint) - 10] + "/models";
    elseif (!models_endpoint:ends_with("/models"))
      models_endpoint = models_endpoint:ends_with("/") ? models_endpoint + "models" | models_endpoint + "/models";
    endif
    headers = {{"Accept", "application/json"}};
    if (this.api_key && typeof(this.api_key) == TYPE_STR && this.api_key != "")
      headers = {@headers, {"Authorization", "Bearer " + this.api_key}};
    endif
    req_start = ftime();
    response = worker_request('curl, {"GET", models_endpoint, "", headers});
    req_end = ftime();
    typeof(response) == TYPE_LIST && length(response) >= 3 || raise(E_INVARG, "Invalid response from LLM models endpoint: " + toliteral(response));
    {status, response_headers, body} = response;
    server_log("LLM models response " + tostr(status) + " time: " + tostr(req_end - req_start) + "s (" + models_endpoint + ")");
    if (status < 200 || status >= 300)
      err = status == 401 || status == 403 ? E_PERM | E_INVARG;
      raise(err, "LLM models API error: HTTP " + tostr(status) + " - " + body);
    endif
    typeof(body) == TYPE_STR || return body;
    body != "" || raise(E_INVARG, "LLM models API returned empty response");
    parsed = parse_json(body);
    if (mode == "raw")
      if (typeof(limit) == TYPE_INT && limit > 0 && typeof(parsed) == TYPE_MAP && maphaskey(parsed, "data") && typeof(parsed["data"]) == TYPE_LIST)
        count = length(parsed["data"]);
        if (count > limit)
          parsed["data"] = (parsed["data"])[1..limit];
        endif
      endif
      return parsed;
    endif
    rows = {};
    if (typeof(parsed) == TYPE_MAP && maphaskey(parsed, "data") && typeof(parsed["data"]) == TYPE_LIST)
      data = parsed["data"];
      for entry in (data)
        if (typeof(entry) == TYPE_MAP)
          id = maphaskey(entry, "id") ? tostr(entry["id"]) | "";
          if (id != "")
            row = ["id" -> id];
            if (maphaskey(entry, "owned_by"))
              row["owned_by"] = tostr(entry["owned_by"]);
            else
              slash = "/" in id;
              slash && (row["owned_by"] = id[1..slash - 1]);
            endif
            maphaskey(entry, "name") && (row["name"] = tostr(entry["name"]));
            maphaskey(entry, "context_length") && (row["context_length"] = entry["context_length"]);
            if (maphaskey(entry, "description") && typeof(entry["description"]) == TYPE_STR)
              desc = entry["description"];
              if (length(desc) > 120)
                desc = desc[1..120] + "...";
              endif
              row["description"] = desc;
            endif
            rows = {@rows, row};
          endif
        endif
      endfor
    else
      return ["endpoint" -> models_endpoint, "count" -> 0, "shown" -> 0, "models" -> {}, "raw" -> parsed];
    endif
    total = length(rows);
    if (limit > 0 && total > limit)
      rows = rows[1..limit];
    endif
    return ["endpoint" -> models_endpoint, "count" -> total, "shown" -> length(rows), "models" -> rows];
  endverb
endobject