object FORMAT_CODE
  name: "Code Block Flyweight Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for code block content. Renders code in fenced blocks with optional language specification for syntax highlighting.";
  override import_export_id = "format_code";

  verb mk (this none this) owner: HACKER flags: "rxd"
    "Create a code block flyweight. Args: (code_content) or (code_content, language)";
    "Code content can be a string or list of strings (one per line)";
    if (length(args) < 1 || length(args) > 2)
      raise(E_INVARG, "Code block requires 1-2 arguments: code content and optional language");
    endif
    code_content = args[1];
    typeof(code_content) != STR && typeof(code_content) != LIST && raise(E_TYPE, "Code content must be a string or list");
    if (length(args) == 2)
      language = args[2];
      typeof(language) != STR && typeof(language) != SYM && raise(E_TYPE, "Language must be a string or symbol");
      return <this, .language = language, {code_content}>;
    else
      return <this, {code_content}>;
    endif
  endverb

  verb compose (this none this) owner: HACKER flags: "rxd"
    {render_for, content_type, event} = args;
    contents = flycontents(this);
    code_content = contents[1];
    if (typeof(code_content) == LIST)
      code_content = code_content:join("\n");
    endif
    language = `tostr(this.language) ! E_PROPNF => ""';
    if (content_type == 'text_djot)
      if (language)
        return "\n```" + language + "\n" + code_content + "\n```\n\n";
      else
        return "\n```\n" + code_content + "\n```\n\n";
      endif
    elseif (content_type == 'text_html)
      if (language)
        code_elem = <$html, {"code", ["class" -> "language-" + language], {code_content}}>;
        return <$html, {"pre", {}, {code_elem}}>;
      else
        return <$html, {"pre", {}, {<$html, {"code", {}, {code_content}}>}}>;
      endif
    else
      return code_content + "\n";
    endif
  endverb

  verb test_code_block_no_language (this none this) owner: HACKER flags: "rxd"
    code_fw = this:mk("hello world");
    typeof(code_fw) == FLYWEIGHT || raise(E_ASSERT("mk should return flyweight"));
    contents = flycontents(code_fw);
    contents[1] == "hello world" || raise(E_ASSERT("Code content should be stored"));
    result = code_fw:compose($player, 'text_djot, {});
    result == "\n```\nhello world\n```\n\n" || raise(E_ASSERT("Djot output wrong: " + toliteral(result)));
    return true;
  endverb

  verb test_code_block_with_language (this none this) owner: HACKER flags: "rxd"
    code_fw = this:mk("def foo():\n    pass", "python");
    typeof(code_fw) == FLYWEIGHT || raise(E_ASSERT("mk should return flyweight"));
    code_fw.language == "python" || raise(E_ASSERT("Language should be stored"));
    result = code_fw:compose($player, 'text_djot, {});
    result == "\n```python\ndef foo():\n    pass\n```\n\n" || raise(E_ASSERT("Djot output wrong: " + toliteral(result)));
    return true;
  endverb

  verb test_code_block_symbol_language (this none this) owner: HACKER flags: "rxd"
    code_fw = this:mk("fn main() {}", 'rust);
    typeof(code_fw) == FLYWEIGHT || raise(E_ASSERT("mk should return flyweight"));
    code_fw.language == 'rust || raise(E_ASSERT("Language should be stored as symbol, got: " + toliteral(code_fw.language)));
    result = code_fw:compose($player, 'text_djot, {});
    result == "\n```rust\nfn main() {}\n```\n\n" || raise(E_ASSERT("Djot output wrong: " + toliteral(result)));
    return true;
  endverb

  verb test_code_block_djot_spacing (this none this) owner: HACKER flags: "rxd"
    "Test that code blocks have proper spacing for djot parsing";
    code_fw = this:mk("line1\nline2\nline3");
    result = code_fw:compose($player, 'text_djot, {});
    "Should start with newline and end with double newline";
    result[1] == "\n" || raise(E_ASSERT("Code block should start with newline"));
    result[$ - 1..$] == "\n\n" || raise(E_ASSERT("Code block should end with double newline, got: " + toliteral(result[$ - 1..$])));
    "Should contain the fence markers";
    "```" in result || raise(E_ASSERT("Code block should contain fence markers"));
    return true;
  endverb

  verb test_code_after_title_djot (this none this) owner: HACKER flags: "rxd"
    "Test that title + code produces valid djot with proper separation";
    title = $format.title:mk("Test Title");
    code = this:mk("test content");
    title_output = title:compose($player, 'text_djot, {});
    code_output = code:compose($player, 'text_djot, {});
    "Concatenate like event system does";
    combined = title_output + code_output;
    "Title should end with double newline";
    "## Test Title\n\n" in title_output || raise(E_ASSERT("Title should end with blank line, got: " + toliteral(title_output)));
    "Code should start with newline";
    code_output[1] == "\n" || raise(E_ASSERT("Code should start with newline"));
    "Combined should have blank line between heading and fence";
    "Pattern should be: ## Title\n\n\n```";
    "## Test Title\n\n\n```" in combined || raise(E_ASSERT("Should have blank line between title and code fence, got: " + toliteral(combined)));
    return true;
  endverb

  verb test_multiline_code_djot (this none this) owner: HACKER flags: "rxd"
    "Test multiline content preserves line breaks in djot output";
    content = "line1\nline2\nline3";
    code_fw = this:mk(content);
    result = code_fw:compose($player, 'text_djot, {});
    "Should contain all three lines";
    "line1" in result || raise(E_ASSERT("Missing line1"));
    "line2" in result || raise(E_ASSERT("Missing line2"));
    "line3" in result || raise(E_ASSERT("Missing line3"));
    "Lines should be separated by newlines within the fence";
    "line1\nline2\nline3" in result || raise(E_ASSERT("Lines not properly separated, got: " + toliteral(result)));
    return true;
  endverb

  verb test_paste_event_flow (this none this) owner: HACKER flags: "rxd"
    "Test the complete @paste event flow to see what djot is generated";
    content = "line1\nline2\nline3";
    title = $format.title:mk("Test pastes");
    code = this:mk(content);
    event = $event:mk_paste($player, title, code);
    "Transform for djot like tell() does";
    output = event:transform_for($player, 'text_djot);
    "Output should be a list of strings";
    typeof(output) == LIST || raise(E_ASSERT("Output should be list, got: " + typeof(output)));
    "Join the output to see the full djot";
    djot_str = "";
    for entry in (output)
      typeof(entry) == STR && (djot_str = djot_str + entry);
    endfor
    "Check the djot has proper structure";
    "## Test pastes" in djot_str || raise(E_ASSERT("Missing title, got: " + toliteral(djot_str)));
    "```" in djot_str || raise(E_ASSERT("Missing code fence, got: " + toliteral(djot_str)));
    "line1\nline2\nline3" in djot_str || raise(E_ASSERT("Missing content, got: " + toliteral(djot_str)));
    return true;
  endverb
endobject