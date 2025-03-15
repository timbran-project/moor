object BLOCK
  name: "Multiline Block Content Flyweight Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  verb mk (this none this) owner: HACKER flags: "rxd"
    return <this, {@args}>;
  endverb

  verb render_as (this none this) owner: HACKER flags: "rxd"
    {content_type, event} = args;
    result = {};
    for line_no in [1..length(this)]
      content = this[line_no];
      if (typeof(content) == str)
        result = {@result, content};
      elseif (typeof(content) == flyweight)
        result = {@result, content:render_as(@args)};
      else
        raise(E_TYPE);
      endif
    endfor
    return result;
  endverb

  verb test_multiline_render (this none this) owner: HACKER flags: "rxd"
    let lines = this:mk("a", "b", "c");
    let result = lines:render_as("text/plain", true);
    length(result) != 3 && raise(E_ASSERT, "content wrong length: " + toliteral(result));
  endverb

endobject
