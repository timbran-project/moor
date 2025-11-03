object LIST
  name: "List Content Flyweight Delegate"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for list content in events.";
  override import_export_id = "list";

  verb mk (this none this) owner: HACKER flags: "rxd"
    "Create list flyweight with optional ordered attribute";
    {content, ?ordered = false} = args;
    typeof(content) != LIST && raise(E_TYPE, "List content must be a list");
    return <this, [ordered -> ordered], {@content}>;
  endverb

  verb compose (this none this) owner: HACKER flags: "rxd"
    "Compose list content into appropriate format";
    {render_for, content_type, event} = args;
    result = {};
    for item in (this)
      if (typeof(item) == STR)
        result = {@result, item};
      elseif (typeof(item) == FLYWEIGHT)
        result = {@result, item:compose(@args)};
      else
        raise(E_TYPE, "List items must be strings or composable flyweights");
      endif
    endfor
    if (content_type == 'text_html)
      "Create li-wrapped items for HTML";
      li_items = {};
      for item in (result)
        li_items = {@li_items, <$html, {"li", {}, {item}}>};
      endfor
      tag = this.ordered ? "ol" | "ul";
      return <$html, {tag, {}, li_items}>;
    endif
    prefix = this.ordered ? "1. " | "* ";
    formatted = {};
    for item in (result)
      formatted = {@formatted, prefix + item};
    endfor
    return formatted:join("\n");
  endverb

  verb test_unordered_list (this none this) owner: HACKER flags: "rxd"
    "Test creating unordered HTML list";
    items = {"Coffee", "Tea", "Milk"};
    list_obj = this:mk(items);
    html_result = list_obj:compose($nothing, 'text_html, $nothing);
    xml_result = html_result:render('text_html);
    parsed = xml_parse(xml_result, LIST);
    expected = {"ul", {"li", {"p", "Coffee"}}, {"li", {"p", "Tea"}}, {"li", {"p", "Milk"}}};
    parsed != expected && return E_ASSERT;
    return true;
  endverb

  verb test_ordered_list (this none this) owner: HACKER flags: "rxd"
    "Test creating ordered HTML list";
    items = {"First", "Second", "Third"};
    list_obj = this:mk(items, true);
    html_result = list_obj:compose($nothing, 'text_html, $nothing);
    xml_result = html_result:render('text_html);
    parsed = xml_parse(xml_result, LIST);
    expected = {"ol", {"li", {"p", "First"}}, {"li", {"p", "Second"}}, {"li", {"p", "Third"}}};
    parsed != expected && return E_ASSERT;
    return true;
  endverb

  verb test_plain_text_output (this none this) owner: HACKER flags: "rxd"
    "Test plain text list output";
    items = {"Apple", "Banana", "Cherry"};
    unordered = this:mk(items);
    ordered = this:mk(items, true);
    plain_unordered = unordered:compose($nothing, 'text_plain, $nothing);
    plain_ordered = ordered:compose($nothing, 'text_plain, $nothing);
    plain_unordered != "* Apple\n* Banana\n* Cherry" && return E_ASSERT;
    plain_ordered != "1. Apple\n1. Banana\n1. Cherry" && return E_ASSERT;
    return true;
  endverb
endobject