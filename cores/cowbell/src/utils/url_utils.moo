object URL_UTILS
  name: "URL Utilities"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: HACKER

  override description = "Utilities for fetching and parsing URL metadata (OpenGraph, meta tags) for link previews.";
  override import_export_hierarchy = {"utils"};
  override import_export_id = "url_utils";

  verb fetch_preview (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Fetch URL and extract OpenGraph/meta preview data.";
    "Args: {url} => map with url, title, description, image, site_name";
    {url} = args;
    result = ["url" -> url, "title" -> "", "description" -> "", "image" -> "", "site_name" -> ""];
    "Fetch the URL";
    headers = {{"User-Agent", "mooR/1.0 (Link Preview)"}};
    try
      response = worker_request('curl, {"GET", url, "", headers});
    except e (ANY)
      return result;
    endtry
    "Parse response";
    if (typeof(response) != LIST || length(response) < 3)
      return result;
    endif
    {status, resp_headers, body} = response;
    if (status < 200 || status >= 300 || typeof(body) != STR)
      return result;
    endif
    "Extract OpenGraph and meta tags";
    result = this:_parse_meta(body, result);
    return result;
  endverb

  verb _parse_meta (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Parse HTML for OpenGraph and meta tags using html_query.";
    {html, result} = args;
    "Query for OpenGraph meta tags";
    og_tags = html_query(html, "meta", ['property -> "og:*"]);
    for tag in (og_tags)
      prop = tag["property"];
      if (prop && index(prop, "og:") == 1)
        key = prop[4..$];
        if (key in {"title", "description", "image", "site_name"} && tag["content"])
          result[key] = tag["content"];
        endif
      endif
    endfor
    "Fallback to standard meta/title tags if OG not found";
    if (!result["title"])
      titles = html_query(html, "title");
      if (length(titles) > 0 && titles[1]["text"])
        result["title"] = titles[1]["text"];
      endif
    endif
    if (!result["description"])
      descs = html_query(html, "meta", ['name -> "description"]);
      if (length(descs) > 0 && descs[1]["content"])
        result["description"] = descs[1]["content"];
      endif
    endif
    return result;
  endverb

  verb to_curie_str (this none this) owner: HACKER flags: "rxd"
    "Convert an object reference to a CURIE string for web-host RESTful paths.";
    "Returns strings like 'uuid:...', 'oid:...' depending on object type.";
    "Usage: $url_utils:to_curie_str(target)";
    {target} = args;
    typeof(target) == OBJ || raise(E_TYPE);
    target_str = tostr(target);
    if (is_uuobjid(target))
      return "uuid:" + target_str[2..$];
    else
      return "oid:" + target_str[2..$];
    endif
  endverb
endobject
