object FORMAT_TABLE
  name: "Table Content Flyweight Delegate"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for table content in events.";
  override import_export_id = "format_table";

  verb mk (this none this) owner: HACKER flags: "rxd"
    "Create table flyweight with headers and rows";
    {headers, rows} = args;
    typeof(headers) != LIST && raise(E_TYPE, "Headers must be a list");
    typeof(rows) != LIST && raise(E_TYPE, "Rows must be a list");
    return <this, [headers -> headers, rows -> rows]>;
  endverb

  verb compose (this none this) owner: HACKER flags: "rxd"
    "Compose table content into appropriate format";
    {render_for, content_type, event} = args;
    headers = this.headers;
    rows = this.rows;
    if (!headers || !rows)
      if (content_type == 'text_html)
        return <$html, {"p", {}, {"(empty table)"}}>;
      else
        return "(empty table)";
      endif
    endif
    if (content_type == 'text_html)
      "Build HTML table structure";
      table_children = {};
      "Add header row if present";
      if (headers)
        header_cells = {};
        for header in (headers)
          header_content = `header:compose(@args) ! E_VERBNF => tostr(header)';
          header_cells = {@header_cells, <$html, {"th", {}, {header_content}}>};
        endfor
        thead = <$html, {"thead", {}, {<$html, {"tr", {}, header_cells}>}}>;
        table_children = {@table_children, thead};
      endif
      "Add body rows";
      body_rows = {};
      for row in (rows)
        row_cells = {};
        for cell in (row)
          cell_content = `cell:compose(@args) ! E_VERBNF => tostr(cell)';
          row_cells = {@row_cells, <$html, {"td", {}, {cell_content}}>};
        endfor
        body_rows = {@body_rows, <$html, {"tr", {}, row_cells}>};
      endfor
      tbody = <$html, {"tbody", {}, body_rows}>;
      table_children = {@table_children, tbody};
      return <$html, {"table", {}, table_children}>;
    endif
    "Plain text table output";
    result = {};
    "Calculate column widths";
    widths = {};
    for i in [1..length(headers)]
      widths = {@widths, length(tostr(headers[i]))};
    endfor
    for row in (rows)
      for i in [1..min(length(row), length(widths))]
        cell_width = length(tostr(row[i]));
        if (cell_width > widths[i])
          widths[i] = cell_width;
        endif
      endfor
    endfor
    "Build header line";
    line = "";
    for i in [1..length(headers)]
      if (i > 1)
        line = line + " | ";
      endif
      line = line + $str_proto:pad_right(tostr(headers[i]), widths[i]);
    endfor
    result = {@result, line};
    "Build separator";
    line = "";
    for i in [1..length(headers)]
      if (i > 1)
        line = line + "-+-";
      endif
      line = line + $str_proto:space(widths[i], "-");
    endfor
    result = {@result, line};
    "Build data rows";
    for row in (rows)
      line = "";
      for i in [1..length(headers)]
        if (i > 1)
          line = line + " | ";
        endif
        cell = i <= length(row) ? tostr(row[i]) | "";
        line = line + $str_proto:pad_right(cell, widths[i]);
      endfor
      result = {@result, line};
    endfor
    return result:join("\n");
  endverb

  verb test_simple_table (this none this) owner: HACKER flags: "rxd"
    "Test creating simple HTML table";
    headers = {"Name", "Age"};
    rows = {{"Alice", "25"}, {"Bob", "30"}};
    table_obj = this:mk(headers, rows);
    html_result = table_obj:compose($nothing, 'text_html, $nothing);
    xml_result = html_result:render('text_html);
    parsed = xml_parse(xml_result, LIST);
    "Verify basic table structure";
    parsed[1] != "table" && return E_ASSERT;
    "Should have thead and tbody";
    length(parsed) < 3 && raise(E_INVARG, "parsed structure: " + toliteral(parsed));
    return true;
  endverb

  verb test_plain_text_table (this none this) owner: HACKER flags: "rxd"
    "Test plain text table output";
    headers = {"Item", "Price"};
    rows = {{"Apple", "$1.00"}, {"Banana", "$0.50"}};
    table_obj = this:mk(headers, rows);
    text_result = table_obj:compose($nothing, 'text_plain, $nothing);
    "Should contain headers and separator";
    !index(text_result, "Item") || !index(text_result, "Price") || !index(text_result, "---") && raise(E_INVARG, "text result: " + toliteral(text_result));
    return true;
  endverb
endobject