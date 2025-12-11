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
    "Parse HTML for OpenGraph and meta tags.";
    {html, result} = args;
    "OpenGraph tags: og:title, og:description, og:image, og:site_name";
    for og_prop in ({"title", "description", "image", "site_name"})
      content = this:_extract_og(html, og_prop);
      if (content)
        result[og_prop] = content;
      endif
    endfor
    "Fallback to standard meta/title tags if OG not found";
    if (!result["title"])
      result["title"] = this:_extract_title(html);
    endif
    if (!result["description"])
      result["description"] = this:_extract_meta_name(html, "description");
    endif
    return result;
  endverb

  verb _extract_og (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Extract OpenGraph property content from HTML.";
    "Looks for <meta property=\"og:NAME\" content=\"VALUE\"> or similar patterns.";
    {html, prop_name} = args;
    og_prop = "og:" + prop_name;
    "Search for the property in various quote styles";
    for pattern in ({"property=\"" + og_prop + "\"", "property='" + og_prop + "'"})
      idx = index(html, pattern);
      if (idx > 0)
        "Find the containing meta tag";
        tag_start = rindex(html[1..idx], "<meta");
        if (tag_start > 0)
          tag_end = index(html[tag_start..$], ">");
          if (tag_end > 0)
            tag = html[tag_start..tag_start + tag_end - 1];
            return this:_extract_attr(tag, "content");
          endif
        endif
      endif
    endfor
    return "";
  endverb

  verb _extract_title (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Extract <title> content from HTML.";
    {html} = args;
    start = index(html, "<title");
    start == 0 && return "";
    "Skip past the opening tag";
    tag_end = index(html[start..$], ">");
    tag_end == 0 && return "";
    content_start = start + tag_end;
    "Find closing tag";
    close = index(html[content_start..$], "</title>");
    close == 0 && return "";
    return html[content_start..content_start + close - 2]:trim();
  endverb

  verb _extract_meta_name (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Extract meta tag content by name attribute.";
    "Looks for <meta name=\"NAME\" content=\"VALUE\">";
    {html, meta_name} = args;
    for pattern in ({"name=\"" + meta_name + "\"", "name='" + meta_name + "'"})
      idx = index(html, pattern);
      if (idx > 0)
        tag_start = rindex(html[1..idx], "<meta");
        if (tag_start > 0)
          tag_end = index(html[tag_start..$], ">");
          if (tag_end > 0)
            tag = html[tag_start..tag_start + tag_end - 1];
            return this:_extract_attr(tag, "content");
          endif
        endif
      endif
    endfor
    return "";
  endverb

  verb _extract_attr (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Extract attribute value from an HTML tag string.";
    {tag, attr_name} = args;
    "Try double quotes first";
    pattern = attr_name + "=\"";
    idx = index(tag, pattern);
    if (idx > 0)
      start = idx + length(pattern);
      end_quote = index(tag[start..$], "\"");
      if (end_quote > 0)
        return tag[start..start + end_quote - 2];
      endif
    endif
    "Try single quotes";
    pattern = attr_name + "='";
    idx = index(tag, pattern);
    if (idx > 0)
      start = idx + length(pattern);
      end_quote = index(tag[start..$], "'");
      if (end_quote > 0)
        return tag[start..start + end_quote - 2];
      endif
    endif
    return "";
  endverb
endobject