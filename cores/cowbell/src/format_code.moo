object FORMAT_CODE
  name: "Code Block Flyweight Delegate"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for code block content. Renders code in fenced blocks with optional language specification for syntax highlighting.";
  override import_export_id = "format_code";

  verb mk (this none this) owner: HACKER flags: "rxd"
    "Create a code block flyweight. Args: (code_string) or (code_string, language)";
    if (length(args) < 1 || length(args) > 2)
      raise(E_INVARG, "Code block requires 1-2 arguments: code content and optional language");
    endif
    code_content = args[1];
    typeof(code_content) != STR && raise(E_TYPE, "Code content must be a string");
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
    language = `tostr(this.language) ! E_PROPNF => ""';
    if (content_type == 'text_djot)
      if (language)
        return "```" + language + "\n" + code_content + "\n```\n";
      else
        return "```\n" + code_content + "\n```\n";
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
    result = code_fw:compose($prog, 'text_djot, {});
    result == "```\nhello world\n```\n" || raise(E_ASSERT("Djot output wrong: " + toliteral(result)));
    return true;
  endverb

  verb test_code_block_with_language (this none this) owner: HACKER flags: "rxd"
    code_fw = this:mk("def foo():\n    pass", "python");
    typeof(code_fw) == FLYWEIGHT || raise(E_ASSERT("mk should return flyweight"));
    code_fw.language == "python" || raise(E_ASSERT("Language should be stored"));
    result = code_fw:compose($prog, 'text_djot, {});
    result == "```python\ndef foo():\n    pass\n```\n" || raise(E_ASSERT("Djot output wrong: " + toliteral(result)));
    return true;
  endverb

  verb test_code_block_symbol_language (this none this) owner: HACKER flags: "rxd"
    code_fw = this:mk("fn main() {}", 'rust);
    typeof(code_fw) == FLYWEIGHT || raise(E_ASSERT("mk should return flyweight"));
    code_fw.language == 'rust || raise(E_ASSERT("Language should be stored as symbol, got: " + toliteral(code_fw.language)));
    result = code_fw:compose($prog, 'text_djot, {});
    result == "```rust\nfn main() {}\n```\n" || raise(E_ASSERT("Djot output wrong: " + toliteral(result)));
    return true;
  endverb
endobject