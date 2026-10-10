object FORMAT_LIST [
  import_export_id -> "format_list",
  import_export_hierarchy -> {"format"}
]
  name: "List Content Flyweight Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  override description (owner: HACKER, flags: "rc") = "Flyweight delegate for list content in events.";

  method mk owner: HACKER
    "Create list flyweight with optional ordered attribute";
    const {content, ?ordered = false, ?columns = false} = args;
    typeof(content) != TYPE_LIST && raise(E_TYPE, "List content must be a list");
    return <this, .ordered = ordered, .columns = columns, {@content}>;
  endmethod

  method compose owner: HACKER
    "Compose each list item while preserving its annotations.";
    const {render_for, content_type, event} = args;
    const {parts, annotations} = $format:compose_parts(flycontents(this), @args);
    if (content_type == 'text_html)
      const items = { <$html, {"li", {}, {part}}> for part in (parts) };
      return $format:result(<$html, {this.ordered ? "ol" | "ul", this.columns ? {"class", "reference-columns"} | {}, items}>, annotations);
    endif
    const prefix = this.ordered ? "1. " | "* ";
    const lines = { prefix + part for part in (parts) };
    const layout = content_type == 'text_djot && this.columns ? "{.reference-columns}\n" | "";
    const body = layout + lines:join("\n");
    return $format:result(content_type == 'text_djot ? "\n" + body + "\n" | body, annotations);
  endmethod

  method test_unordered_list owner: HACKER
    "Test creating unordered HTML list";
    items = {"Coffee", "Tea", "Milk"};
    list_obj = this:mk(items);
    html_result = list_obj:compose($nothing, 'text_html, $nothing);
    xml_result = html_result:render('text_html);
    parsed = xml_parse(xml_result, TYPE_LIST);
    expected = {"ul", {"li", "Coffee"}, {"li", "Tea"}, {"li", "Milk"}};
    parsed != expected && raise(E_ASSERT, "Expected: " + toliteral(expected) + " Got: " + toliteral(parsed));
    return true;
  endmethod

  method test_ordered_list owner: HACKER
    "Test creating ordered HTML list";
    items = {"First", "Second", "Third"};
    list_obj = this:mk(items, true);
    html_result = list_obj:compose($nothing, 'text_html, $nothing);
    xml_result = html_result:render('text_html);
    parsed = xml_parse(xml_result, TYPE_LIST);
    expected = {"ol", {"li", "First"}, {"li", "Second"}, {"li", "Third"}};
    parsed != expected && return E_ASSERT;
    return true;
  endmethod

  method test_plain_text_output owner: HACKER
    "Test plain text list output";
    items = {"Apple", "Banana", "Cherry"};
    unordered = this:mk(items);
    ordered = this:mk(items, true);
    plain_unordered = unordered:compose($nothing, 'text_plain, $nothing);
    plain_ordered = ordered:compose($nothing, 'text_plain, $nothing);
    plain_unordered != "* Apple\n* Banana\n* Cherry" && return E_ASSERT;
    plain_ordered != "1. Apple\n1. Banana\n1. Cherry" && return E_ASSERT;
    return true;
  endmethod
endobject
