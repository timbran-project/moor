## mooR cowbell

[mooR](https://timbran.org/moor.html) is a from-scratch rewrite of the LambdaMOO server in Rust,
designed for building persistent, programmable social environments. It's a multi-user virtual
environment where users can build and program the world around them while they're in it.

Cowbell is a from-scratch "core" database for mooR - the starter objects and code that provide the
foundation for building social spaces. It's designed specifically for use with mooR's bundled
[web client](https://codeberg.org/timbran/moor/src/branch/main/web-client), a rich web
application that connects to mooR server.

While taking inspiration from classic MOOs and TinyMU* systems, cowbell is built to
leverage the capabilities of contemporary web browsers or mobile devices rather than line-based `telnet`
like old-school MUDs.

### Vision

With the ongoing crisis and "enshittification" of commercial social media, we think people
crave alternatives - platforms that prioritize community, creativity, and user ownership over
engagement metrics and ad revenue.

Cowbell aims to be a toolkit for building rich, social experiences that can compete with commercial
messaging platforms (Discord, Slack, Instagram, Facebook Messenger) while preserving MOO's creative,
text-first culture. The goal: interaction quality matching contemporary messaging apps combined with
MOO's whimsical, creative spirit and user empowerment. Colourful, dynamic interfaces that still
fundamentally centre text, story, and social connection.

While the initial focus is on social interaction, the architecture is designed to support MUD/game/RPG
mechanics as well - combat systems, quests, skill checks, inventory management. These can be built on
top of the event and behaviour systems without requiring framework changes.

**Core principles:**

- **Web-first**: Rich content (HTML, Djot markdown, structured data) as first-class citizens
- **Event-driven**: Semantic narrative events with perspective rendering, not dumb string output
- **Language features**: Leverages mooR's lexical scopes, symbols, booleans, list comprehensions,
  maps, and flyweights
- **Composable**: Building blocks that work together without requiring code for common patterns
- **Accessible**: Text-first design that works naturally with screen readers and keyboard navigation
- **Version-controlled**: Objdef format enables proper source control; in-MOO changes merge back to
  repo

### Current Implementation Status

**Event System:**

- Event architecture with perspective rendering (`event.moo`, `event_receiver.moo`)
- Substitution system for perspective-dependent text (you/Bob, pronouns) (`sub.moo`)
- Event receiver base class for broadcasting to connections
- Pronoun system with customizable pronouns (`pronouns.moo`)

**Rich Content & Formatting:**

- HTML rendering system (`html.moo`)
- Format objects: block, list, table, title, code (`format*.moo`)
- Rich look descriptions with structured content (`look.moo`)
- Support for multiple content types (text/plain, text/html, text/djot)

**Core Objects:**

- `$player` with multi-connection support, inventory, pronouns (`player.moo`)
- `$room` with event broadcasting, enterfunc/exitfunc (`room.moo`)
- `$thing` basic object prototype (`thing.moo`)
- `$area` and `$passage` for spatial organization (`area.moo`, `passage.moo`)
- Prototype objects for primitives: `$str_proto`, `$list_proto`, `$int_proto`

**Systems:**

- Authentication with argon2 password hashing (`password.moo`, `login.moo`)
- Capability-based security for fine-grained permissions (`root.moo`, `grant_utils.moo`, `@grant`)
- Object matching system (`match.moo`)
- Permission roles: arch_wizard, wizard, builder, programmer, hacker
- Relational/graph system for object relationships (`relation.moo`) with datalog-style unification.
- Basic object management: `@create`, `@recycle`
- Basic room creation and passage/tunneling: `@build`, `@dig`

**World Content:**

- Starting area with connected rooms (`first_area.moo`, `first_room.moo`, `second_room.moo`)
- Passage-based navigation with route finding (`passage.moo`, `area.moo`, `first_area_passages.moo`)

**Not Yet Implemented:**

- Additional building commands
- Property and verb management commands
- Composable behaviour/trait system (lockable, openable, container, etc.)
- Social action verbs (hug, wave, bonk, etc.)
- Rich client presentation system for UI panels
- NPC and dialog systems
- Web client UI components (verb palette, object browser, etc.)

(Note: This is a from-scratch implementation. While some concepts are inspired by LambdaCore/JHCore,
we're not porting existing code wholesale - we're building idiomatically for mooR's advanced
features.)

### A Rich-Event-Driven Story for the user

Traditional MOO cores use `notify(player, "Bob says, \"Hello\"")` - dumb string dumping with no
context about what's happening. The client can't make smart rendering decisions.

Cowbell is designed to work with mooR's web client, which can understand and render structured events.
Instead of plain strings, the core sends **structured narrative events with metadata:**

```moo
// Create event with semantic information
event = $event:mk_say(player, "Hello everyone");

// Event is a flyweight containing:
// - Semantic slots (actor, timestamp, event type)
// - Template content with substitution flyweights
// - Delegate for behaviour ($event)

// Events transform themselves per viewer for perspective
// "You say" vs "Bob says", pronouns, etc.
for recipient in (room.contents)
  recipient:tell(event);  // Renders "you" or "Bob" as appropriate
endfor

// Web client receives both rendered content AND metadata
// Metadata enables smart rendering:
// - 'say events → speech bubbles
// - 'emote events → italicized styling
// - 'whisper events → private styling
// - 'room_action events → ambient styling
```

The web client uses this to provide:

- **Rich rendering**: Speech bubbles for dialogue, emphasis for emotes, colour coding, images, avatars
- **Perspective rendering**: Same event shows different text to different viewers
- **Accessibility**: Screen readers get semantic context (this is speech, this is an action, this is a system message),
  not just raw text. Structured events provide navigation landmarks and allow users to filter by event type. Content
  type negotiation means users can request plain text, semantic HTML with ARIA labels, or other formats that work best
  for their assistive technology.
- **Extensibility**: New event types work without client changes (graceful degradation)
- **Rich content**: Events can carry HTML, Djot markdown, structured data

### Capability-Based Security

Traditional MOO permission models rely on flag checking and ownership. Cowbell uses **capability
passing** for fine-grained, delegatable permissions:

```moo
// Issue a capability that grants specific operations
setup_cap = $root:issue_capability(new_player, {
  'set_player_flag,
  'set_name_aliases,
  'set_password,
  'move
});

// Capability can be passed to trusted code
// Recipient can only perform allowed operations
setup_cap:set_password("secret");  // Works
setup_cap:chparent(other_obj);     // Fails - not in capability list
```

This allows passing limited authority to code without transferring full ownership. Capabilities can be
revoked without changing object ownership, making it possible to grant temporary or conditional access.
You can audit which code has which capabilities, and follow the principle of least privilege by granting
only the specific operations needed rather than broad permissions.

## Development

To compile / validate your changes use the provided `Makefile`

- `make` will use the latest mooR release (via docker) to compiler / import "*.moo" into a local
  generated old-style textdump file, for the purpose of validation
- `make clean` will destroy said file
- `make gen.objdir` will build a new objdef dir from the local changes.
- `make rebuild` will build a new objdef dir with your local changes and then (WARNING) _overwrite_
  your local changes. Think of this is as a formatting step (for prior to commit, etc)

To run a moor instance with the provided core database, first make sure you don't have any old
database files lying around locally, and then run

`docker compose up`

## Contribution

Cowbell is in early days - workflows and conventions haven't been fully refined for external
contributions yet. That said, we're happy to help and educate if you're interested in contributing.
Come chat with us on [Discord](https://discord.gg/Ec94y5983z) to discuss ideas and get guidance.

## Design Goals & Roadmap

The goal is to build a toolkit that enables:

1. **Social Experience**: Interaction quality matching contemporary messaging platforms while
   preserving MOO's creative, text-first culture
2. **Composable Building**: Pre-made behaviours (lockable, openable, container) that work without
   writing code
3. **Rich Authoring Tools**: Both traditional MOO commands and web-based editors
4. **Mobile-Friendly**: Touch interactions, gesture-based navigation, responsive layouts
5. **Accessible by Default**: Screen reader support, keyboard navigation, semantic HTML, customizable
   presentation

**Key planned features:**

- **Rich event vocabulary**: Social events (say, emote, whisper, hug, wave), environmental events
  (arrive, depart, look), system events (inventory, who, errors), and game events (combat, quests)
- **Multi-connection support**: Multiple simultaneous connections per player (phone + laptop, different
  views/layouts per connection)
- **Composable behaviours**: Mix-and-match traits (lockable, openable, container, wearable, etc.) to
  build objects without code
- **Web UI patterns**: Speech bubbles for dialogue, verb palettes for actions, rich room/object cards,
  mobile-friendly touch interactions
- **Presentation system**: Server-triggered UI panels (object browser, verb editor, property editor,
  room builder)
- **Template library**: Pre-configured objects (doors, containers, furniture) for rapid building

**Long-term vision**: A platform where:

- New users can build rich, interactive spaces without programming
- Experienced builders can rapidly prototype with pre-made behaviours
- The web client competes with Discord, Slack, and Instagram for interaction quality
- Mobile users have a first-class experience
- Everyone can participate regardless of ability
