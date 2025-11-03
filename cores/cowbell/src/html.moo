object HTML
  name: "HTML Tree Flyweight"
  parent: ROOT
  owner: HACKER

  override description = "Flyweight delegate for HTML tree structures.";
  override import_export_id = "html";

  verb render (this none this) owner: HACKER flags: "rxd"
    {content_type} = args;
    tags = this:to_xml_tag();
    return to_xml(tags);
  endverb

  verb to_xml_tag (this none this) owner: HACKER flags: "rxd"
    "We have to descend our tree and turn nodes into to_xml renderable elements, and then run to_xml after we're done";
    "Our form is { tag, attributes, children }, where children can be either terminal nodes, or flyweights themselves";
    {tag, attributes, children} = {this[1], this[2], this[3]};
    results = {};
    for entry in (children)
      if (typeof(entry) == FLYWEIGHT)
        "Entry is a flyweight and thus something that can itself be rendered to xml tag form,, we hope...";
        result = entry:to_xml_tag();
      elseif (typeof(entry) == LIST)
        "Entry is a list of things we should be able to do rendering for...";
        e = {};
        for subentry in (entry)
          if (typeof(subentry) == FLYWEIGHT)
            e = {@e, subentry:to_xml_tag()};
          elseif (typeof(subentry) == LIST)
            " Need to handle nested lists recursively ";
            e = {@e, subentry};
          else
            e = {@e, {"p", {}, subentry}};
          endif
        endfor
        result = e;
      else
        result = {"p", {}, entry};
      endif
      results = {@results, result};
    endfor
    return {tag, attributes, @results};
  endverb
endobject