object SUB
    name: "Multiline Block Content Flyweight Delegate"
    parent: ROOT
    owner: HACKER
    readable: true

    verb render_as (this none this) owner: HACKER flags: "rd"
        {content_type, event} = args;
    endverb
endobject
