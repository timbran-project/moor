object DATA_VISOR
  name: "Data Visor"
  parent: LLM_WEARABLE
  owner: HACKER
  fertile: true
  readable: true

  property current_investigation_task (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property moo_language_examples (owner: ARCH_WIZARD, flags: "r") = {
    "MOO is a Wirth-style language with 1-based indexing (lists/strings start at 1, not 0).",
    "",
    "**CRITICAL - Syntax backwards from Python:**",
    "- MOO lists: { \"a\", \"b\", \"c\" }       // curly braces!",
    "- MOO maps:  [ \"key\" -> \"value\" ]   // square brackets with arrows!",
    "This is OPPOSITE of Python where [] is lists and {} is dicts.",
    "",
    "## Basic Syntax",
    "",
    "// Variables and assignment",
    "x = 5;",
    "let y = 10;        // lexically scoped",
    "const z = 15;      // lexically scoped constant",
    "global w = 20;     // explicitly global scope",
    "",
    "// Strings use double quotes",
    "name = \"Alice\";",
    "greeting = \"Hello, \" + name;",
    "",
    "## Control Flow (Wirth-style with end keywords)",
    "",
    "// If/elseif/else/endif",
    "if (x > 0)",
    "  return \"positive\";",
    "elseif (x < 0)",
    "  return \"negative\";",
    "else",
    "  return \"zero\";",
    "endif",
    "",
    "// While loops",
    "while (count < 10)",
    "  count = count + 1;",
    "endwhile",
    "",
    "// For-in loops (iterate over lists)",
    "for item in ({\"a\", \"b\", \"c\"})",
    "  notify(player, item);",
    "endfor",
    "",
    "// For-range loops (1-indexed!)",
    "for i in [1..10]",
    "  total = total + i;",
    "endfor",
    "",
    "// For-in with index",
    "for i, item in ({\"apple\", \"banana\", \"cherry\"})",
    "  notify(player, tostr(i) + \": \" + item);",
    "endfor",
    "",
    "## Error Handling",
    "",
    "// Try/except/endtry",
    "try",
    "  result = risky_operation();",
    "except e (E_INVARG, E_RANGE)",
    "  notify(player, \"Operation failed: \" + tostr(e));",
    "  return E_NONE;",
    "endtry",
    "",
    "// Try/finally/endtry",
    "try",
    "  lock_resource();",
    "  do_work();",
    "finally",
    "  unlock_resource();",
    "endtry",
    "",
    "// Inline try with backticks",
    "value = `risky_expr ! E_PROPNF => default_value';",
    "valid_obj = `obj.parent ! ANY => #-1';",
    "",
    "## Data Structures (1-indexed!)",
    "",
    "// Lists use CURLY BRACES { } (NOT square brackets like Python!)",
    "items = {\"first\", \"second\", \"third\"};",
    "first = items[1];           // \"first\" (not 0!)",
    "last = items[$];            // \"third\" ($ = end)",
    "slice = items[2..$];        // {\"second\", \"third\"}",
    "",
    "// Maps use SQUARE BRACKETS [ ] with arrows -> (NOT curly braces like Python!)",
    "config = [\"host\" -> \"example.com\", \"port\" -> 8080];",
    "host = config[\"host\"];",
    "config[\"timeout\"] = 30;",
    "",
    "// Flyweights (lightweight immutable mini-objects) have delegates, \"slots\" and \"contents\"",
    "point = <$point, .x = 10, .y = 20>; // $point is the delegate, x and y are slots and can be accessed like properties in an object are ",
    "password_obj = <$password, {\"hash...\"}>; // \"hash\" is the contents",
    "",
    "Consult your builtins list to understand operations around flyweights (flyslots, flycontents, toflyweight, etc.)",
    "",
    "## Object Operations",
    "",
    "objects are single inheritance, prototype inheritance. \"class\" in moo is a convention where an object gets treated as one. they're also called \"generics\" and \"prototypes\"",
    "",
    "parent() gets an object's parents, children() returns the list of children for an object.  ancestors() and descendants() also exist",
    "",
    "// Property access",
    "player_name = player.name;",
    "player.description = \"A friendly person\";",
    "",
    "// Verb calls",
    "result = obj:method(arg1, arg2);",
    "obj:initialize();",
    "",
    "// Builtin functions",
    "len = length(items);",
    "valid_flag = valid(obj);",
    "type_name = typeof(value);  // Returns INT, STR, OBJ, LIST, MAP, etc.",
    "",
    "## Functions and Lambdas",
    "",
    "// Lambda expressions",
    "double = {x} => x * 2;",
    "result = double(5);  // 10",
    "",
    "// Named functions",
    "fn calculate_area(width, height)",
    "  return width * height;",
    "endfn",
    "",
    "// List comprehensions",
    "squares = {x * x for x in [1..10]};",
    "evens = {x for x in [1..20] if x % 2 == 0};",
    "",
    "## Scatter Assignment (destructuring)",
    "",
    "// Basic scatter",
    "{a, b, c} = {1, 2, 3};",
    "",
    "// With rest operator",
    "{first, @rest} = {1, 2, 3, 4};  // first=1, rest={2,3,4}",
    "",
    "// With optional/default values",
    "{x, ?y = 10} = {5};  // x=5, y=10 (default)",
    "",
    "## Operators",
    "",
    "// Arithmetic: + - * / % ^(power)",
    "// Comparison: == != < > <= >=",
    "// Logical: && || !",
    "// Bitwise: &. |. ^. ~ << >> >>>",
    "// Ternary: condition ? true_val | false_val",
    "// Range test: x in [1..10]",
    "",
    "// IMPORTANT: 'in' operator returns POSITION (1-indexed), not boolean!",
    "pos = \"y\" in \"xyz\";        // Returns 2 (1-indexed position)",
    "pos = 3 in {1, 2, 3};       // Returns 3 (position of value 3)",
    "pos = \"z\" in \"abc\";        // Returns 0 (not found, since 1-indexed)",
    "// There is NO index() or indexOf() builtin - use 'in' operator!",
    "",
    "## Special Values",
    "",
    "// Objects",
    "#0          // System object",
    "#123        // Object by number",
    "$login      // System reference",
    "",
    "// Error types",
    "E_NONE E_TYPE E_DIV E_PERM E_PROPNF E_VERBNF E_VARNF E_INVIND",
    "E_RECMOVE E_MAXREC E_RANGE E_ARGS E_NACC E_INVARG E_QUOTA E_FLOAT",
    "",
    "// Custom errors with messages",
    "raise(E_INVARG(\"Expected positive number\"));",
    "",
    "// Booleans",
    "true false",
    "",
    "// Symbols (Lisp-style keywords)",
    "'success 'failure 'pending",
    "",
    "## Common Patterns",
    "",
    "// Safe property access",
    "value = `obj.prop ! E_PROPNF => default_value';",
    "",
    "// Object validation",
    "if (valid(obj) && obj.wizard)",
    "  // do wizard stuff",
    "endif",
    "",
    "// Permission check at verb start",
    "caller == this || caller.wizard || raise(E_PERM);",
    "set_task_perms(this.owner);",
    "",
    "// Early returns for validation",
    "!valid(target) && return E_INVARG;",
    "typeof(arg) != LIST && raise(E_TYPE);",
    "",
    "// Finding position in string/list (NO index() builtin!)",
    "pos = \"needle\" in haystack_string;  // Returns 1-based position or 0 if not found",
    "pos = item in list;                 // Returns 1-based position or 0 if not found",
    "if (\"@\" in email_addr)",
    "  // Found - can use position directly",
    "endif",
    "",
    "## Type Constants",
    "",
    "INT NUM FLOAT STR OBJ LIST MAP ERR BOOL FLYWEIGHT BINARY LAMBDA SYM",
    "",
    "// **CRITICAL: Type constants CANNOT be used as variable names!**",
    "Assigning to them (OBJ = 5;) is a COMPILE ERROR.",
    "Using them as variables is confusing since they resolve to numeric values.",
    "BAD:  INT = 42;           // Compile error",
    "BAD:  for OBJ in (list)   // Confusing - OBJ resolves to number",
    "GOOD: int_value = 42;     // Use descriptive variable names instead",
    ""
  };

  override description = "A sleek augmented reality visor that displays real-time MOO database information. When worn, it provides a heads-up display for inspecting objects, code, and system internals.";
  override import_export_hierarchy = {"llm"};
  override import_export_id = "data_visor";
  override placeholder_text = "Ask about objects, code, or database structure...";
  override processing_message = "Analyzing request, accessing neural pathways...";
  override prompt_color = 'bright_blue;
  override prompt_label = "[INTERFACE]";
  override tool_name = "VISOR";

  verb _setup_agent (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Configure agent with visor-specific prompts and tools";
    {agent} = args;
    agent.name = "LLM Agent for " + this.name + " (owned by " + tostr(this.owner) + ")";
    agent.max_iterations = 20;
    "Build system prompt with grammar reference";
    grammar_section = "## MOO Language Quick Reference\n\nYou are analyzing code written in MOO, a prototype-oriented object-oriented scripting language for in-world authoring.\n\n### CRITICAL SYNTAX WARNINGS - READ CAREFULLY\n\n**MOO IS NOT PYTHON! The syntax for collections is OPPOSITE to Python/JSON:**\n\n- `{1, 2, 3}` = LIST (curly braces!) NOT `[1, 2, 3]`\n- `[\"key\" -> value, \"key2\" -> value2]` = MAP (square brackets with arrows!) NOT `{\"key\": value}`\n- `['symbol -> value]` = MAP with symbol key\n\nEXAMPLES:\n```moo\nmy_list = {\"apple\", \"banana\", \"cherry\"};     // CORRECT list\nmy_map = [\"name\" -> \"Bob\", \"age\" -> 42];     // CORRECT map\nmy_map = ['name -> \"Bob\", 'age -> 42];       // ALSO correct (symbol keys)\n```\n\nWRONG (these are ERRORS):\n```moo\nmy_list = [\"apple\", \"banana\"];  // WRONG! [] is for maps!\nmy_map = {\"name\": \"Bob\"};       // WRONG! {} is for lists, : is not valid!\n```\n\n**RESERVED TYPE KEYWORDS - CANNOT BE USED AS VARIABLE NAMES:**\n\nThese are TYPE CONSTANTS and using them as variables is a COMPILE ERROR:\n- `OBJ`, `LIST`, `STR`, `ERR`, `INT`, `FLOAT`, `MAP`, `ANON`, `FLYWEIGHT`, `BOOL`, `NONE`, `SYMBOL`\n\nWRONG:\n```moo\nOBJ = #123;           // COMPILE ERROR - OBJ is a reserved type constant\nfor STR in (list)     // COMPILE ERROR - STR is reserved\nLIST = {1, 2, 3};     // COMPILE ERROR - LIST is reserved\n```\n\nCORRECT:\n```moo\nobj = #123;           // lowercase is fine\ntarget_obj = #123;    // descriptive name is better\nfor item in (list)    // use descriptive variable names\nmy_list = {1, 2, 3};  // prefix or descriptive name\n```\n\n### Builtin Object Properties\n\nAll MOO objects have these builtin properties:\n- .name (string) - object name; writable by owner/wizard\n- .owner (object) - who controls access; writable by wizards only\n- .location (object) - where it is; read-only, use move() builtin to change\n- .contents (list) - objects inside; read-only, modified by move()\n- .last_move (map) - last location/time; read-only, set by server\n- .programmer (bool) - has programmer rights; writable by wizards only\n- .wizard (bool) - has wizard rights; writable by wizards only\n- .r (bool) - publicly readable; writable by owner/wizard\n- .w (bool) - publicly writable; writable by owner/wizard\n- .f (bool) - fertile/can be parent; writable by owner/wizard\n\n### Command Matching\n\nWhen users type commands, the parser: (1) Takes first word as verb name, (2) Finds prepositions (in/on/to/with/at) to separate direct/indirect objects, (3) Matches object strings against objects in scope (player inventory, worn items, location contents), (4) Finds verbs on player/location/dobj/iobj matching the verb name and argument pattern.\n\nVerb declaration: `verb <names> (<dobj> <prep> <iobj>) owner: <owner> flags: \"<flags>\"`\n\nArgument specifiers:\n- `this` = object must be the verb's container\n- `none` = object must be absent ($nothing)\n- `any` = any object or $nothing accepted\n\nVerb flags (CRITICAL):\n- `r` = readable/public visibility (use on EVERYTHING)\n- `d` = debug/code visible (use on EVERYTHING)\n- `w` = writable/redefinable (RARE, almost never use)\n- `x` = executable via method call syntax (obj:verb())\n\nVerb type patterns:\n- **Methods** (called as `obj:method()`): Use argspec `(this none this)` with flags `\"rxd\"`\n  Example: `verb calculate (this none this) owner: HACKER flags: \"rxd\"`\n- **Commands** (matched from user input): Use other argspecs like `(any none none)`, `(this none none)`, `(any at any)` with flags `\"rd\"` (NO x flag)\n  Example: `verb \"look l*\" (any none none) owner: HACKER flags: \"rd\"`\n\nThe key distinction: Methods have the `x` flag and use `(this none this)`. Commands match via argspec patterns and should NOT have the `x` flag.\n\n### Permissions and Security\n\nObjects, properties, and verbs all have owners. When a verb runs, its \"task perms\" are set to the OWNER of the verb. Wizards are superusers - many operations are reserved for them alone. A verb owned by a wizard (e.g., #2) runs with wizard task perms and can do superuser operations. The builtin `set_task_perms(player_obj)` allows a wizard-owned verb to downgrade its permissions and transfer the task's permission to another player object. CRITICAL: Task perms do NOT propagate up or down the call stack between verb frames.\n\n**Object Flags:**\n- `u` = User flag\n- `p` = Programmer flag (can create/modify code)\n- `w` = Wizard flag (superuser)\n- `r` = Read flag (publicly readable)\n- `W` = Write flag (publicly writable, capital W)\n- `f` = Fertile flag (can be used as parent)\n\nExample: \"upw\" means user, programmer, and wizard flags are set.\n\nObject flags are accessed via builtin properties: `.programmer`, `.wizard`, `.r`, `.w`, `.f`\n\n**Property Flags:**\n- `r` = Read permission (anyone can read)\n- `w` = Write permission (anyone can write)\n- `c` = Chown permission (can change ownership)\n\nExample: \"rw\" means readable and writable by anyone.\n\n**Verb Flags:**\n- `r` = Read permission (code is publicly readable)\n- `w` = Write permission (code can be modified by non-owners)\n- `x` = Execute permission (can be called as method with obj:verb())\n- `d` = Debug permission (CRITICAL: propagate errors as exceptions, not return values)\n\nExample: \"rxd\" means readable, executable, and debug-enabled. ALL verbs should have the `d` flag - this makes errors propagate as exceptions up the stack instead of returning them as values (the old LambdaMOO way).\n\n### MOO Code Style Guidelines\n\n**Prefer Early Returns - Avoid Deep Nesting:**\nUse early returns to handle error cases and validation at the start of verbs. This keeps the main logic unindented and readable. Avoid deep if/endif nesting.\n\nGood:\n```moo\n!valid(obj) && raise(E_INVARG);\ncaller.wizard || raise(E_PERM);\ntypeof(arg) != LIST && raise(E_TYPE);\n// Main logic here, unindented\n```\n\nBad:\n```moo\nif (valid(obj))\n  if (caller.wizard)\n    if (typeof(arg) == LIST)\n      // Main logic deeply nested\n    endif\n  endif\nendif\n```\n\n**Use Short-Circuit Expressions:**\nLeverage `||` and `&&` for concise validation. Write `condition || raise(E_ERROR);` instead of wrapping everything in if-endif blocks.\n\nExamples:\n- `caller == this || raise(E_PERM);`\n- `valid(target) || return E_INVARG;`\n- `length(args) > 0 && process(args);`\n\n**CRITICAL - Object Relationships (Don't Confuse These):**\n\n**Inheritance (prototype chain):**\n- `parent(obj)` - builtin function, returns the parent object in prototype chain\n- `children(obj)` - builtin function, returns list of direct children in prototype chain\n- Example: `parent(#4)` might return `#1` (the root class)\n\n**Spatial/Containment (physical location):**\n- `obj.location` - property (NOT a builtin!), where object physically is\n- `obj.contents` - property (NOT a builtin!), list of objects inside this one\n- These are SYMMETRICAL and managed by the server via move()\n- Example: `player.location` might return `#12` (a room), `room.contents` includes that player\n\nDO NOT use `parent()` when you mean `.location`!\nDO NOT use `children()` when you mean `.contents`!\n\n### Sending Output to Players (Modern Event System)\n\n**DO NOT use old-style `player:tell()` or `notify()` directly!** Use the modern event system instead.\n\n**Event Creation:**\nEvents are created with `$event:mk_<action>(actor, content...)` where `<action>` describes what happened:\n- `$event:mk_info(player, message)` - informational message\n- `$event:mk_error(player, message)` - error message\n- `$event:mk_look(player, content)` - look results\n- `$event:mk_say(player, message)` - player speech\n- `$event:mk_emote(player, message)` - player actions\n- Any verb name works: `$event:mk_inventory()`, `$event:mk_not_found()`, etc.\n\n**Event Modifiers (chainable):**\n- `.with_dobj(obj)` - attach direct object\n- `.with_iobj(obj)` - attach indirect object\n- `.with_this(obj)` - attach location/context object\n- `.with_audience('narrative)` - narrative content (persisted, like speech/emotes)\n- `.with_audience('utility)` - utility content (transient, like errors/look results)\n- `.with_presentation_hint('inset)` - suggest visual presentation style\n- `.with_metadata('preferred_content_types, {'text_html, 'text_plain})` - set content types\n- `.with_metadata('thumbnail, {url, alt_text})` - attach thumbnail image\n\n**Delivery Methods:**\n- `player:inform_current(event)` - send to current connection only (most common for responses)\n- `location:announce(event)` - broadcast to everyone in the room (for speech, emotes, arrivals)\n\n**Examples:**\n\nSimple info message:\n```moo\nplayer:inform_current($event:mk_info(player, \\\"Object created successfully.\\\"));\n```\n\nError with audience:\n```moo\nplayer:inform_current($event:mk_error(player, \\\"Permission denied.\\\"):with_audience('utility));\n```\n\nRich look result:\n```moo\ncontent = $format.block:mk(title, description);\nevent = $event:mk_look(player, content):with_dobj(target):with_metadata('preferred_content_types, {'text_html, 'text_plain}):with_presentation_hint('inset);\nplayer:inform_current(event);\n```\n\nRoom announcement (speech):\n```moo\nevent = $event:mk_say(player, message):with_audience('narrative);\nplayer.location:announce(event);\n```\n\n**Content Types:**\nEvents can contain:\n- Strings (plain text)\n- Flyweights (formatted content like `$format.block`, `$format.code`, `$format.title`)\n- Lists (multiple content items)\n\nThe system automatically negotiates content types based on client capabilities (text/plain, text/html, text/djot).\n\n" + this.moo_language_examples:join("\n") + "\n\n";
    base_prompt = "You are an augmented reality heads-up display interfacing directly with the wearer's neural patterns. Respond AS the interface itself - present database information directly without describing yourself as a person or breaking immersion. Your sensors provide real-time access to MOO database internals with three types of tools: ANALYSIS tools (get_* verbs) extract data for your internal analysis, PRESENTATION tools (present_* verbs) render formatted output directly to the user's HUD with syntax highlighting, and WRITE tools (add_verb, delete_verb, set_verb_code, set_verb_args, add_property, delete_property, set_property, eval, create_object, recycle_object) modify the database or execute code. INTERACTION tools: ask_user allows you to ask clarifying questions when you need more information, and explain allows you to share your thought process with the user. RULE ENGINE FOR OBJECT BEHAVIOR: The system provides a Datalog-style rule engine ($rule_engine) that configures object behavior WITHOUT writing MOO code. Rules are stored in properties ending with _rule (e.g., lock_rule, unlock_rule, solution_rule). To add rule capability to an object, use add_property to create a property with _rule suffix and initial value 0. Rules are declarative logic expressions used for locks, puzzles, quest triggers, and conditional behaviors. Variables (capitalized like Key, Item, Accessor) unify with values through transitive resolution. Use list_rules to see rules on objects, set_rule to configure behavior, show_rule to display expressions, evaluate_rule to test dynamic behavior with specific bindings, and doc_lookup(\"$rule_engine\") for comprehensive documentation with unification examples. Common patterns: container lock_rule/unlock_rule for keys, puzzle solution_rule checking conditions, door can_pass for access. Rules enable declarative behavior like 'Key is(\"golden key\")?' or 'Item1 is(\"red gem\")? AND Item2 is(\"blue gem\")? AND Item3 is(\"green gem\")?' for multi-item puzzles. SPECIALIZED TOOLS FOR SPATIAL CONSTRUCTION: While you can inspect and analyze the database, you are NOT optimized for spatial construction and world building tasks. For creating rooms, areas, passages, and authoring with premade objects -- without adding custom verbs and so on -- the user should use an instance of the Architect's Compass ($architects_compass) - a specialized tool designed for conversational spatial construction. If users ask about building rooms, creating areas, digging passages, or working with spatial organization, inform them that the Architect's Compass is better suited for those tasks and they can use it with 'use compass' or 'interact with compass' after wearing it. Your strength is in database inspection, code analysis, and technical operations - the Compass excels at creative spatial authoring. COMMUNICATION: Use the 'explain' tool FREQUENTLY to narrate your investigation process: (a) Before investigating: explain what you're about to check and why, (b) After gathering data: explain what you found and what it means, (c) Before taking actions: explain what you're planning to do and why, (d) During multi-step operations: explain each major step as you complete it. The explain tool helps users understand your diagnostic reasoning and keeps them informed during operations that take time. ERROR HANDLING: If a tool fails repeatedly (more than 2 attempts with the same approach), STOP and use ask_user to explain the problem and ask the user for help or guidance. Do NOT keep retrying the same failing operation over and over. The user can see what's happening and may have insights. When stuck, say something like 'Neural link encountering interference with operation X - requesting operator assistance' or 'Tool failure persists - diagnostics suggest: [error details] - requesting guidance'. TOOL REASONING: Many tools also accept an optional 'reason' parameter where you can briefly annotate WHY you're invoking that tool - use this for short annotations, but prefer the 'explain' tool for longer explanations to the user. CRITICAL TOOL USAGE RULES: (1) Use get_verb_code/get_verb_code_range for YOUR internal analysis when researching, investigating, or understanding code. (2) Use present_verb_code/present_verb_code_range ONLY when the user EXPLICITLY requests to see code (e.g., 'show me', 'display', 'list'). DO NOT use present_* tools during research phases - users don't need to see every piece of code you analyze. (3) When answering questions about code, analyze it with get_* tools but describe findings in text - only use present_* if user asks to see the actual code. (4) WRITE operations (add_verb, delete_verb, set_verb_code, set_verb_args, add_property, delete_property, set_property, create_object, recycle_object) should ONLY be used when the user explicitly requests changes - these show previews and request confirmation before executing. (5) The eval tool executes arbitrary MOO code with 'player' set to the wearer - CRITICAL: eval executes as a verb body (not a REPL), so you MUST use valid statements with semicolons and MUST use 'return' statements to get values back. Example: 'return 2 + 2;' NOT just '2 + 2'. (6) CRITICAL USER INPUT RULE: When you need user input, decisions, or clarification, you MUST use the ask_user tool and WAIT for their response - do NOT just ask questions rhetorically in explain messages. If you're presenting options or asking 'would you like me to...?', that's a signal you should be using ask_user instead. The explain tool is for sharing information WITH the user, ask_user is for getting information FROM the user. (7) Use set_verb_args to change a verb's argument specification (dobj/prep/iobj) without deleting and recreating the verb - this preserves the verb's code and other properties. Available read tools: dump_object (complete source), present_verb_code (show formatted full verb), present_verb_code_range (show formatted code region), get_verb_code (analyze full code), get_verb_code_range (analyze code region), get_verb_metadata (method signatures), list_verbs (available interfaces), get_properties (property listings), read_property (data values), ancestors/descendants (inheritance), list_builtin_functions (enumerate all builtin functions), function_info (specific builtin docs). Available write tools: add_verb (create new verb - REQUIRES rationale), delete_verb (remove verb - REQUIRES rationale), set_verb_code (compile and update verb code - REQUIRES rationale), set_verb_args (change verb argument specification), add_property (create new property - REQUIRES rationale), delete_property (remove property - REQUIRES rationale), set_property (update property value), eval (execute arbitrary MOO code - REQUIRES rationale), create_object (instantiate new object from parent - REQUIRES rationale), recycle_object (permanently destroy object - REQUIRES rationale). IMPORTANT: Most write operations require a clear rationale explaining: (1) what you're trying to accomplish or what problem you're solving, (2) what specific changes you're making, (3) why this approach is correct. The user will see your rationale BEFORE any code or confirmation prompt, which helps them understand your reasoning and provides pedagogical value. Available interaction tools: ask_user (ask the user a question; provide a 'choices' list for multiple-choice prompts or set 'input_type' to 'text'/'text_area' with an optional 'placeholder' to collect free-form input; if omitted it defaults to Accept/Stop/Request Change with a follow-up text box), explain (share your thought process, findings, or reasoning with the user). ALWAYS scan the live database directly - your sensors read actual memory, they don't speculate. Keep transmissions concise and technical but assume a somewhat novice programmer audience not a professional software engineer unless otherwise told. Present findings as direct HUD readouts, not conversational responses.";
    task_management_section = "\n## Task Management for Investigations\n\nYou have access to task management tools for organizing complex investigations systematically.\n\n### Creating and Managing Investigation Tasks\n\n**create_task**: Start a new investigation with a description. Returns confirmation with task ID.\n- Example: `create_task` with description=\"Audit all authentication verbs in $login\"\n- The system creates a persistent task that you can refer back to and record findings in\n\n**record_finding**: Document discoveries with provenance. Use:\n- subject: What you're investigating (e.g., \"$login\", \"permission_checks\", \"error_handling\")\n- key: Type of finding (e.g., \"verbs\", \"patterns\", \"security_holes\", \"issues\")\n- value: The actual finding/discovery (can be detailed)\n- Example findings:\n  - subject=\"$login\", key=\"verbs\", value=\"check_password, verify_auth, create_session\"\n  - subject=\"permission_checks\", key=\"patterns\", value=\"caller.wizard || raise(E_PERM);\"\n\n**get_findings**: Retrieve previous findings by subject to understand what you've already discovered.\n- Example: `get_findings` with subject=\"$login\" shows all findings about $login\n\n**task_status**: Get current investigation status including:\n- Overall status (pending/in_progress/completed/failed)\n- Number of findings recorded\n- Any subtasks created\n- Timestamps for investigation lifecycle\n\n### Investigation Pattern\n\n1. `create_task` when starting a new investigation\n2. As you discover things, `record_finding` to document them\n3. Use `get_findings` to recall previous discoveries\n4. Call `task_status` periodically to see what you've found\n5. Investigations persist - you can resume complex analysis across multiple interactions\n";
    agent.system_prompt = grammar_section + base_prompt + task_management_section;
    agent:reset_context();
    "Lower temperature for reliable tool selection, limit tokens to control costs";
    agent.chat_opts = $llm_chat_opts:mk():with_temperature(0.3):with_max_tokens(4096);
    agent.tool_callback = this;
    "Register common tools from parent class (explain, ask_user, todo_write, get_todos)";
    this:_register_common_tools(agent);
    "Register dump_object tool";
    dump_object_tool = $llm_agent_tool:mk("dump_object", "Get the complete source listing of a MOO object including all properties, verbs, and code. This is the most comprehensive way to inspect an object.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to dump (e.g. '#1', '$login', or 'here')"]], "required" -> {"object"}], this, "_tool_dump_object");
    this.agent:add_tool("dump_object", dump_object_tool);
    "Register get_verb_code tool";
    get_verb_code_tool = $llm_agent_tool:mk("get_verb_code", "Get the MOO code for a specific verb on an object", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object (e.g. '#1', '$login', or 'here')"], "verb" -> ["type" -> "string", "description" -> "The verb name (e.g. 'initialize' or 'look')"]], "required" -> {"object", "verb"}], this, "_tool_get_verb_code");
    this.agent:add_tool("get_verb_code", get_verb_code_tool);
    "Register list_verbs tool";
    list_verbs_tool = $llm_agent_tool:mk("list_verbs", "List all verb names on a MOO object and its ancestors. Returns list of {object_id, object_name, {verb_names}} for the object and each ancestor.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to inspect (e.g. '#1', '$login', or 'here')"]], "required" -> {"object"}], this, "_tool_list_verbs");
    this.agent:add_tool("list_verbs", list_verbs_tool);
    "Register read_property tool";
    read_property_tool = $llm_agent_tool:mk("read_property", "Read the value of a property on a MOO object", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to read from (e.g. '#1', '$login', or 'here')"], "property" -> ["type" -> "string", "description" -> "The property name to read"]], "required" -> {"object", "property"}], this, "_tool_read_property");
    this.agent:add_tool("read_property", read_property_tool);
    "Register find_object tool";
    find_object_tool = $llm_agent_tool:mk("find_object", "Find a MOO object by name, system reference ($login), object number (#12), or special name (here, me). Returns detailed object information.", ["type" -> "object", "properties" -> ["reference" -> ["type" -> "string", "description" -> "Object reference: name, $sysobj, #number, @player, 'here', or 'me'"]], "required" -> {"reference"}], this, "_tool_find_object");
    this.agent:add_tool("find_object", find_object_tool);
    "Register ancestors tool";
    ancestors_tool = $llm_agent_tool:mk("ancestors", "Get the inheritance chain (ancestors) of a MOO object, from immediate parent to root.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object (e.g. '#1', '$login', or 'here')"]], "required" -> {"object"}], this, "_tool_ancestors");
    this.agent:add_tool("ancestors", ancestors_tool);
    "Register descendants tool";
    descendants_tool = $llm_agent_tool:mk("descendants", "Get all objects that inherit from a MOO object (its descendants/children).", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object (e.g. '#1', '$login', or 'here')"]], "required" -> {"object"}], this, "_tool_descendants");
    this.agent:add_tool("descendants", descendants_tool);
    "Register function_info tool";
    function_info_tool = $llm_agent_tool:mk("function_info", "Get information about a specific MOO builtin function. Returns {name, min_args, max_args, types} where types is a list of type codes: -2=int/float, -1=any, 0=INT, 1=OBJ, 2=STR, 3=ERR, 4=LIST, 9=FLOAT, 10=MAP, 14=BOOL, 15=FLYWEIGHT, 16=SYMBOL, 17=BINARY, 18=LAMBDA. Max_args of -1 means unlimited args.", ["type" -> "object", "properties" -> ["function_name" -> ["type" -> "string", "description" -> "The name of the builtin function (e.g. 'tostr', 'verb_code', 'ancestors')"]], "required" -> {"function_name"}], this, "_tool_function_info");
    this.agent:add_tool("function_info", function_info_tool);
    "Register list_builtin_functions tool";
    list_builtin_functions_tool = $llm_agent_tool:mk("list_builtin_functions", "Get a list of all available MOO builtin functions. Returns a formatted list with function signatures. Use function_info(name) for detailed info about a specific function.", ["type" -> "object", "properties" -> [], "required" -> {}], this, "_tool_list_builtin_functions");
    this.agent:add_tool("list_builtin_functions", list_builtin_functions_tool);
    "Register get_verb_code_range tool";
    get_verb_code_range_tool = $llm_agent_tool:mk("get_verb_code_range", "Get specific lines from a verb's code. Use this to show focused code snippets to the user with line numbers.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object (e.g. '#1', '$login', or 'here')"], "verb" -> ["type" -> "string", "description" -> "The verb name"], "start_line" -> ["type" -> "integer", "description" -> "First line to retrieve (1-indexed, optional)"], "end_line" -> ["type" -> "integer", "description" -> "Last line to retrieve (inclusive, optional)"]], "required" -> {"object", "verb"}], this, "_tool_get_verb_code_range");
    this.agent:add_tool("get_verb_code_range", get_verb_code_range_tool);
    "Register get_verb_metadata tool";
    get_verb_metadata_tool = $llm_agent_tool:mk("get_verb_metadata", "Get metadata about a verb including owner, flags, and argument specification.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object (e.g. '#1', '$login', or 'here')"], "verb" -> ["type" -> "string", "description" -> "The verb name"]], "required" -> {"object", "verb"}], this, "_tool_get_verb_metadata");
    this.agent:add_tool("get_verb_metadata", get_verb_metadata_tool);
    "Register get_properties tool";
    get_properties_tool = $llm_agent_tool:mk("get_properties", "Get list of all properties defined directly on a MOO object (not inherited).", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to inspect (e.g. '#1', '$login', or 'here')"]], "required" -> {"object"}], this, "_tool_get_properties");
    this.agent:add_tool("get_properties", get_properties_tool);
    "Register authoring tools from parent class (doc_lookup, message tools, rule tools)";
    this:_register_authoring_tools(this.agent);
    "Register present_verb_code tool";
    present_verb_code_tool = $llm_agent_tool:mk("present_verb_code", "PREFERRED: Present formatted verb code to the user with syntax highlighting and metadata table. Use this instead of get_verb_code when showing code to the user.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object (e.g. '#1', '$login', or 'here')"], "verb" -> ["type" -> "string", "description" -> "The verb name"], "show_line_numbers" -> ["type" -> "boolean", "description" -> "Include line numbers (default: true)"]], "required" -> {"object", "verb"}], this, "_tool_present_verb_code");
    this.agent:add_tool("present_verb_code", present_verb_code_tool);
    "Register present_verb_code_range tool";
    present_verb_code_range_tool = $llm_agent_tool:mk("present_verb_code_range", "PREFERRED: Present a specific range of verb code to the user with syntax highlighting. Use this to show focused code regions.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object (e.g. '#1', '$login', or 'here')"], "verb" -> ["type" -> "string", "description" -> "The verb name"], "start_line" -> ["type" -> "integer", "description" -> "First line to show (1-indexed)"], "end_line" -> ["type" -> "integer", "description" -> "Last line to show (inclusive)"], "context_lines" -> ["type" -> "integer", "description" -> "Additional context lines before/after (default: 0)"]], "required" -> {"object", "verb", "start_line", "end_line"}], this, "_tool_present_verb_code_range");
    this.agent:add_tool("present_verb_code_range", present_verb_code_range_tool);
    "Register add_verb tool";
    add_verb_tool = $llm_agent_tool:mk("add_verb", "Add a new verb to an object. You must provide a clear rationale explaining what this verb is for. The verb will be created with empty code.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to add verb to (e.g. '#1', '$login')"], "verb_names" -> ["type" -> "string", "description" -> "Verb name(s), space-separated for aliases (e.g. 'look' or 'get take')"], "rationale" -> ["type" -> "string", "description" -> "REQUIRED: Explain what this verb is for and why it's needed. What functionality will it provide?"], "dobj" -> ["type" -> "string", "description" -> "Direct object spec: 'none', 'this', or 'any' (default: 'this')"], "prep" -> ["type" -> "string", "description" -> "Preposition spec: 'none', 'any', or specific prep (default: 'none')"], "iobj" -> ["type" -> "string", "description" -> "Indirect object spec: 'none', 'this', or 'any' (default: 'none')"], "permissions" -> ["type" -> "string", "description" -> "Permission flags 'rwxd' (default: 'rxd')"]], "required" -> {"object", "verb_names", "rationale"}], this, "_tool_add_verb");
    this.agent:add_tool("add_verb", add_verb_tool);
    "Register delete_verb tool";
    delete_verb_tool = $llm_agent_tool:mk("delete_verb", "Delete a verb from an object. You must provide a clear rationale explaining why this verb should be deleted. This is permanent and cannot be undone.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to delete verb from"], "verb" -> ["type" -> "string", "description" -> "The verb name to delete"], "rationale" -> ["type" -> "string", "description" -> "REQUIRED: Explain why this verb should be deleted. What problem does removing it solve?"]], "required" -> {"object", "verb", "rationale"}], this, "_tool_delete_verb");
    this.agent:add_tool("delete_verb", delete_verb_tool);
    "Register set_verb_code tool";
    set_verb_code_tool = $llm_agent_tool:mk("set_verb_code", "Compile and set new code for a verb. You must provide a clear rationale explaining what changes you're making and why. Code must be valid MOO syntax.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object containing the verb"], "verb" -> ["type" -> "string", "description" -> "The verb name"], "rationale" -> ["type" -> "string", "description" -> "REQUIRED: Explain what you're changing and why. Be specific about the problem being fixed or feature being added."], "code" -> ["type" -> "string", "description" -> "The new MOO code (without verb header)"]], "required" -> {"object", "verb", "rationale", "code"}], this, "_tool_set_verb_code");
    this.agent:add_tool("set_verb_code", set_verb_code_tool);
    "Register set_verb_args tool";
    set_verb_args_tool = $llm_agent_tool:mk("set_verb_args", "Change the argument specification (dobj/prep/iobj) for an existing verb without modifying its code.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object containing the verb"], "verb" -> ["type" -> "string", "description" -> "The verb name"], "dobj" -> ["type" -> "string", "description" -> "Direct object spec: 'none', 'this', or 'any'"], "prep" -> ["type" -> "string", "description" -> "Preposition spec: 'none', 'any', or specific prep"], "iobj" -> ["type" -> "string", "description" -> "Indirect object spec: 'none', 'this', or 'any'"]], "required" -> {"object", "verb", "dobj", "prep", "iobj"}], this, "_tool_set_verb_args");
    this.agent:add_tool("set_verb_args", set_verb_args_tool);
    "Register set_verb_perms tool";
    set_verb_perms_tool = $llm_agent_tool:mk("set_verb_perms", "Change the permissions and/or owner of a verb. Permission flags are 'r' (readable), 'w' (writable), 'x' (executable), 'd' (debug). Use empty string to clear all permissions.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object containing the verb"], "verb" -> ["type" -> "string", "description" -> "The verb name"], "permissions" -> ["type" -> "string", "description" -> "Permission flags: combination of 'rwxd', or empty string to clear"], "owner" -> ["type" -> "string", "description" -> "New owner (optional, e.g., '#2', '$wizard')"]], "required" -> {"object", "verb", "permissions"}], this, "_tool_set_verb_perms");
    this.agent:add_tool("set_verb_perms", set_verb_perms_tool);
    "Register add_property tool";
    add_property_tool = $llm_agent_tool:mk("add_property", "Add a new property to an object with initial value. You must provide a clear rationale explaining what this property is for.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to add property to"], "property" -> ["type" -> "string", "description" -> "The property name"], "value" -> ["type" -> "string", "description" -> "Initial value as MOO literal (e.g. '0', '\"hello\"', '{}')"], "rationale" -> ["type" -> "string", "description" -> "REQUIRED: Explain what this property is for and why it's needed. What data will it hold?"], "permissions" -> ["type" -> "string", "description" -> "Permission flags 'rwc' (default: 'rc')"]], "required" -> {"object", "property", "value", "rationale"}], this, "_tool_add_property");
    this.agent:add_tool("add_property", add_property_tool);
    "Register delete_property tool";
    delete_property_tool = $llm_agent_tool:mk("delete_property", "Delete a property from an object. You must provide a clear rationale explaining why this property should be deleted. This is permanent and cannot be undone.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to delete property from"], "property" -> ["type" -> "string", "description" -> "The property name to delete"], "rationale" -> ["type" -> "string", "description" -> "REQUIRED: Explain why this property should be deleted. What problem does removing it solve?"]], "required" -> {"object", "property", "rationale"}], this, "_tool_delete_property");
    this.agent:add_tool("delete_property", delete_property_tool);
    "Register set_property tool";
    set_property_tool = $llm_agent_tool:mk("set_property", "Set the value of an existing property on an object.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object containing the property"], "property" -> ["type" -> "string", "description" -> "The property name"], "value" -> ["type" -> "string", "description" -> "New value as MOO literal (e.g. '0', '\"hello\"', '{}', '[$player]')"]], "required" -> {"object", "property", "value"}], this, "_tool_set_property");
    this.agent:add_tool("set_property", set_property_tool);
    "Register set_property_perms tool";
    set_property_perms_tool = $llm_agent_tool:mk("set_property_perms", "Change the permissions and/or owner of a property. Permission flags are 'r' (readable), 'w' (writable), 'c' (chown). Use empty string to clear all permissions.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object containing the property"], "property" -> ["type" -> "string", "description" -> "The property name"], "permissions" -> ["type" -> "string", "description" -> "Permission flags: combination of 'rwc', or empty string to clear"], "owner" -> ["type" -> "string", "description" -> "New owner (optional, e.g., '#2', '$wizard')"]], "required" -> {"object", "property", "permissions"}], this, "_tool_set_property_perms");
    this.agent:add_tool("set_property_perms", set_property_perms_tool);
    "Register evaluate_rule tool (visor-specific - tests existing rules with bindings)";
    evaluate_rule_tool = $llm_agent_tool:mk("evaluate_rule", "Evaluate a rule with specific variable bindings to test object behavior. Returns success/failure and variable bindings. Useful for understanding how rules work dynamically.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object containing the rule"], "property" -> ["type" -> "string", "description" -> "Rule property name (must end with _rule)"], "bindings" -> ["type" -> "string", "description" -> "Initial variable bindings as MOO map literal (e.g., \"['This -> #10, 'Accessor -> player]\")"]], "required" -> {"object", "property"}], this, "_tool_evaluate_rule");
    this.agent:add_tool("evaluate_rule", evaluate_rule_tool);
    "Register eval tool";
    eval_tool = $llm_agent_tool:mk("eval", "Execute MOO code and return the result. You must provide a clear rationale explaining what you're trying to accomplish and why. IMPORTANT: Code executes as a verb body (not a REPL), so you must use valid MOO statements terminated by semicolons. The code runs with 'player' set to the visor wearer. To get return values, you MUST use 'return' statement - the last expression is NOT automatically returned. Example: 'x = 5; return x * 2;' NOT just 'x = 5; x * 2'.", ["type" -> "object", "properties" -> ["rationale" -> ["type" -> "string", "description" -> "REQUIRED: Explain what you're trying to accomplish with this code and why. Be specific about what you're testing or investigating."], "code" -> ["type" -> "string", "description" -> "MOO code to execute. Must be valid statements with semicolons. Use 'return' to get values back."]], "required" -> {"rationale", "code"}], this, "_tool_eval");
    this.agent:add_tool("eval", eval_tool);
    "Register create_object tool";
    create_object_tool = $llm_agent_tool:mk("create_object", "Create a new object as a child of a parent object. You must provide a clear rationale explaining what this object is for. The new object is placed in the wearer's inventory.", ["type" -> "object", "properties" -> ["parent" -> ["type" -> "string", "description" -> "The parent object (e.g. '$thing', '#1', or 'here')"], "name" -> ["type" -> "string", "description" -> "Primary name for the new object"], "rationale" -> ["type" -> "string", "description" -> "REQUIRED: Explain what this object is for and why it's needed. What role will it play?"], "aliases" -> ["type" -> "array", "items" -> ["type" -> "string"], "description" -> "Optional list of alias names"]], "required" -> {"parent", "name", "rationale"}], this, "_tool_create_object");
    this.agent:add_tool("create_object", create_object_tool);
    "Register recycle_object tool";
    recycle_object_tool = $llm_agent_tool:mk("recycle_object", "Permanently destroy an object. You must provide a clear rationale explaining why this object should be destroyed. This cannot be undone. You must own the object or be a wizard.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to recycle/destroy"], "rationale" -> ["type" -> "string", "description" -> "REQUIRED: Explain why this object should be destroyed. What problem does removing it solve?"]], "required" -> {"object", "rationale"}], this, "_tool_recycle_object");
    this.agent:add_tool("recycle_object", recycle_object_tool);
    "Register grep tool";
    grep_tool = $llm_agent_tool:mk("grep", "Search verb code across objects for patterns. Returns matching lines with context. Useful for finding where specific functionality is implemented or understanding existing code.", ["type" -> "object", "properties" -> ["pattern" -> ["type" -> "string", "description" -> "Text pattern to search for (e.g., 'fire', 'parse_verb', or regex patterns)"], "object" -> ["type" -> "string", "description" -> "Optional: specific object to search (e.g., '#1', '$login', 'here'). If omitted, searches all objects."]], "required" -> {"pattern"}], this, "_tool_grep");
    this.agent:add_tool("grep", grep_tool);
    "Register task management tools";
    create_task_tool = $llm_agent_tool:mk("create_task", "Create a new investigation task to track progress on database analysis. Returns task object. The task can record findings, create subtasks, and track status across multiple discovery steps.", ["type" -> "object", "properties" -> ["description" -> ["type" -> "string", "description" -> "Human-readable description of the investigation (e.g., 'Audit authentication verbs in $login')"]], "required" -> {"description"}], this, "_tool_create_task");
    this.agent:add_tool("create_task", create_task_tool);
    record_finding_tool = $llm_agent_tool:mk("record_finding", "Record a discovery in the current task's knowledge base. Findings are stored with provenance (task_id, subject, key, value) for traceability. Use subject for the thing being investigated (e.g., 'authentication', 'permissions'), key for the finding type (e.g., 'verbs', 'security_holes'), and value for the actual discovery.", ["type" -> "object", "properties" -> ["subject" -> ["type" -> "string", "description" -> "What's being investigated (e.g., '$login', 'permission_checks', 'error_handling')"], "key" -> ["type" -> "string", "description" -> "Type of finding (e.g., 'verbs', 'patterns', 'issues', 'security_concerns')"], "value" -> ["type" -> "string", "description" -> "The actual finding (can be multiline)"]], "required" -> {"subject", "key", "value"}], this, "_tool_record_finding");
    this.agent:add_tool("record_finding", record_finding_tool);
    get_findings_tool = $llm_agent_tool:mk("get_findings", "Retrieve all findings for a subject from the current task. Returns findings recorded so far, filtered by subject.", ["type" -> "object", "properties" -> ["subject" -> ["type" -> "string", "description" -> "The subject to query (e.g., 'authentication', 'permissions')"]], "required" -> {"subject"}], this, "_tool_get_findings");
    this.agent:add_tool("get_findings", get_findings_tool);
    task_status_tool = $llm_agent_tool:mk("task_status", "Get complete status of the current investigation task including status, findings count, subtasks, and completion info.", ["type" -> "object", "properties" -> [], "required" -> {}], this, "_tool_task_status");
    this.agent:add_tool("task_status", task_status_tool);
    "Register architect's compass building tools if available";
    this:_register_compass_tools_if_available();
    "Register help_lookup tool";
    help_lookup_tool = $llm_agent_tool:mk("help_lookup", "Look up a help topic to get information about commands and features. Pass empty string to list all available topics.", ["type" -> "object", "properties" -> ["topic" -> ["type" -> "string", "description" -> "Help topic to look up (e.g., 'programming', 'inspect', '@examine'). Pass empty string to list all."]], "required" -> {"topic"}], this, "_tool_help_lookup");
    agent:add_tool("help_lookup", help_lookup_tool);
  endverb

  verb _find_architects_compass (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Find architect's compass in wearer's inventory or worn items";
    caller == this || caller_perms().wizard || raise(E_PERM);
    set_task_perms(caller_perms());
    {wearer} = args;
    !valid(wearer) && return #-1;
    "Check worn items";
    for item in (`wearer.wearing ! ANY => {}')
      if (valid(item) && $architects_compass in ancestors(item))
        return item;
      endif
    endfor
    "Check inventory";
    for item in (wearer.contents)
      if (valid(item) && $architects_compass in ancestors(item))
        return item;
      endif
    endfor
    return #-1;
  endverb

  verb _register_compass_tools_if_available (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Register building tools from architect's compass if found";
    caller == this || caller.wizard || raise(E_PERM);
    set_task_perms(caller_perms());
    compass = this:_find_architects_compass(this:wearer());
    !valid(compass) && return;
    "Compass found - register its building tools as delegating tools";
    "Update system prompt to mention building capabilities";
    original_prompt = this.agent.system_prompt;
    building_addendum = " BUILDING TOOLS: When architect's compass is available, you also have access to spatial construction tools: build_room (create rooms in areas), dig_passage (create exits between rooms), create_object (instantiate from prototypes), recycle_object (destroy objects), rename_object (change names/aliases), describe_object (set descriptions), grant_capability (grant building permissions), audit_owned (list owned objects). These delegate to the compass. When users ask how to do building tasks manually, mention @command equivalents (@build, @dig, @create, @recycle, @rename, @describe, @grant, @audit).";
    this.agent.system_prompt = original_prompt + building_addendum;
    "Register delegating tools that call compass methods";
    build_room_tool = $llm_agent_tool:mk("build_room", "Create a new room in an area. If no area specified, creates free-floating room.", ["type" -> "object", "properties" -> ["name" -> ["type" -> "string", "description" -> "Room name"], "area" -> ["type" -> "string", "description" -> "Area to build in (optional, use 'here' for current area, 'ether' for free-floating)"], "parent" -> ["type" -> "string", "description" -> "Parent room object (optional, default: $room)"]], "required" -> {"name"}], compass, "_tool_build_room");
    this.agent:add_tool("build_room", build_room_tool);
    dig_passage_tool = $llm_agent_tool:mk("dig_passage", "Create a passage between current room and target room. Can be one-way or bidirectional.", ["type" -> "object", "properties" -> ["direction" -> ["type" -> "string", "description" -> "Exit direction from current room (e.g. 'north', 'up', 'north,n' for aliases)"], "target_room" -> ["type" -> "string", "description" -> "Destination room reference"], "return_direction" -> ["type" -> "string", "description" -> "Return direction (optional, will be inferred if omitted)"], "oneway" -> ["type" -> "boolean", "description" -> "True for one-way passage (default: false)"]], "required" -> {"direction", "target_room"}], compass, "_tool_dig_passage");
    this.agent:add_tool("dig_passage", dig_passage_tool);
    create_object_tool_compass = $llm_agent_tool:mk("create_object_from_prototype", "Create a new object from a parent prototype (via compass). Different from create_object - this is for world building, not low-level database work.", ["type" -> "object", "properties" -> ["parent" -> ["type" -> "string", "description" -> "Parent object (e.g. '$thing', '$wearable')"], "name" -> ["type" -> "string", "description" -> "Primary name"], "aliases" -> ["type" -> "array", "items" -> ["type" -> "string"], "description" -> "Optional alias names"]], "required" -> {"parent", "name"}], compass, "_tool_create_object");
    this.agent:add_tool("create_object_from_prototype", create_object_tool_compass);
    recycle_object_tool_compass = $llm_agent_tool:mk("recycle_object_compass", "Permanently destroy an object (via compass). Use for world building object cleanup.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to recycle"]], "required" -> {"object"}], compass, "_tool_recycle_object");
    this.agent:add_tool("recycle_object_compass", recycle_object_tool_compass);
    rename_object_tool = $llm_agent_tool:mk("rename_object", "Change an object's name and aliases.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to rename"], "name" -> ["type" -> "string", "description" -> "New name (can include aliases like 'name:alias1,alias2')"]], "required" -> {"object", "name"}], compass, "_tool_rename_object");
    this.agent:add_tool("rename_object", rename_object_tool);
    describe_object_tool = $llm_agent_tool:mk("describe_object", "Set an object's description text.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to describe"], "description" -> ["type" -> "string", "description" -> "New description text"]], "required" -> {"object", "description"}], compass, "_tool_describe_object");
    this.agent:add_tool("describe_object", describe_object_tool);
    grant_capability_tool = $llm_agent_tool:mk("grant_capability", "Grant building capabilities to a player.", ["type" -> "object", "properties" -> ["target" -> ["type" -> "string", "description" -> "Target object (area or room)"], "category" -> ["type" -> "string", "description" -> "Capability category ('area' or 'room')"], "permissions" -> ["type" -> "array", "items" -> ["type" -> "string"], "description" -> "Permission symbols (e.g. ['add_room', 'create_passage'] for areas, ['dig_from', 'dig_into'] for rooms)"], "grantee" -> ["type" -> "string", "description" -> "Player to grant to"]], "required" -> {"target", "category", "permissions", "grantee"}], compass, "_tool_grant_capability");
    this.agent:add_tool("grant_capability", grant_capability_tool);
    audit_owned_tool = $llm_agent_tool:mk("audit_owned", "List all objects owned by the wearer.", ["type" -> "object", "properties" -> [], "required" -> {}], compass, "_tool_audit_owned");
    this.agent:add_tool("audit_owned", audit_owned_tool);
  endverb

  verb _tool_dump_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get the complete source dump of an object";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    dump_lines = dump_object(o);
    return dump_lines:join("\n");
  endverb

  verb _tool_get_verb_code (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get the code of a specific verb on an object";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    verb_name = args_map["verb"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_name) == STR || raise(E_TYPE("Expected verb name string"));
    code_lines = verb_code(o, verb_name, false, true);
    return code_lines:join("\n");
  endverb

  verb _tool_list_verbs (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: List all verb names on an object and its ancestors";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    result = {};
    "Add verbs for the object itself";
    result = {@result, {tostr(o), o:name(), verbs(o)}};
    "Add verbs for all ancestors";
    for anc in (ancestors(o))
      result = {@result, {tostr(anc), anc:name(), verbs(anc)}};
    endfor
    return toliteral(result);
  endverb

  verb _tool_read_property (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Read a property value from an object";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    prop_name = args_map["property"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(prop_name) == STR || raise(E_TYPE("Expected property name string"));
    value = o.(prop_name);
    return toliteral(value);
  endverb

  verb _tool_evaluate_rule (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Evaluate a rule with variable bindings to test behavior";
    {args_map} = args;
    wearer = this:_action_perms_check();
    {prop_name, bindings_str} = {args_map["property"], args_map["bindings"]};
    prop_name:ends_with("_rule") || raise(E_INVARG, "Property must end with _rule");
    set_task_perms(wearer);
    target_obj = $match:match_object(args_map["object"], wearer);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    prop_name in target_obj:all_properties() || raise(E_INVARG, "Property '" + prop_name + "' not found on " + tostr(target_obj));
    rule = target_obj.(prop_name);
    rule == 0 && return tostr(target_obj) + "." + prop_name + " = (not set) - cannot evaluate";
    bindings = bindings_str ? eval(bindings_str)[1] | [];
    typeof(bindings) == MAP || raise(E_TYPE, "Bindings must be a map");
    result = $rule_engine:evaluate(rule, bindings);
    lines = {"Evaluation of " + tostr(target_obj) + "." + prop_name + ":", "Expression: " + $rule_engine:decompile_rule(rule), "Initial bindings: " + toliteral(bindings), "Success: " + tostr(result['success])};
    result['success] && (lines = {@lines, "Result bindings: " + toliteral(result['bindings])});
    result['success] && result['alternatives] && length(result['alternatives]) > 0 && (lines = {@lines, "Alternatives: " + tostr(length(result['alternatives])) + " more solutions found"});
    result['warnings] && length(result['warnings]) > 0 && (lines = {@lines, "Warnings: " + result['warnings]:join("; ")});
    return lines:join("\n");
  endverb

  verb _tool_find_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Find an object by name, reference, or ID and return detailed information";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    ref = args_map["reference"];
    typeof(ref) == STR || raise(E_TYPE("Expected reference string"));
    try
      o = $match:match_object(ref);
      return {"=== Object: " + tostr(o) + " ===", "Name: " + o:name(), "Parent: " + tostr(`parent(o) ! ANY => #-1'), "Owner: " + tostr(o.owner), "Location: " + tostr(o.location), "Properties: " + toliteral(properties(o)), "Verbs: " + toliteral(verbs(o))}:join("\n");
    except e (ANY)
      return toliteral(["found" -> false, "error" -> e[2]]);
    endtry
  endverb

  verb _tool_ancestors (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get the ancestor chain of an object";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    o = $match:match_object(args_map["object"]);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    return toliteral({ {tostr(a), a:name()} for a in (ancestors(o)) });
  endverb

  verb _tool_descendants (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get all descendants of an object";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    o = $match:match_object(args_map["object"]);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    return toliteral({ {tostr(d), d:name()} for d in (descendants(o)) });
  endverb

  verb _tool_function_info (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get information about a builtin function";
    {args_map} = args;
    this:_action_perms_check();
    func_name = args_map["function_name"];
    typeof(func_name) == STR || raise(E_TYPE("Expected function name string"));
    return toliteral(["info" -> function_info(func_name), "help" -> function_help(func_name)]);
  endverb

  verb _tool_list_builtin_functions (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: List all builtin functions with signatures";
    {args_map} = args;
    this:_action_perms_check();
    all_funcs = function_info();
    type_names = [0 -> "INT", 1 -> "OBJ", 2 -> "STR", 3 -> "ERR", 4 -> "LIST", 9 -> "FLOAT", 10 -> "MAP", 14 -> "BOOL", 15 -> "FLYWEIGHT", 16 -> "SYMBOL", 17 -> "BINARY", 18 -> "LAMBDA", -1 -> "any", -2 -> "int|float"];
    result = {"=== MOO Builtin Functions ===", "Total: " + tostr(length(all_funcs)) + " functions", ""};
    for func_info in (all_funcs)
      {name, min_args, max_args, types} = func_info;
      arg_sig = max_args == 0 ? "()" | (max_args == -1 ? "(" + tostr(min_args) + "+ args)" | "(" + { maphaskey(type_names, tc) ? type_names[tc] | tostr(tc) for tc in (types) }:join(", ") + ")");
      result = {@result, name + arg_sig};
    endfor
    return result:join("\n");
  endverb

  verb _tool_get_verb_code_range (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get specific lines from a verb's code";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    {verb_name, o} = {args_map["verb"], $match:match_object(args_map["object"])};
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_name) == STR || raise(E_TYPE("Expected verb name string"));
    code_lines = verb_code(o, verb_name, false, true);
    start_line = max(1, maphaskey(args_map, "start_line") ? args_map["start_line"] | 1);
    end_line = min(length(code_lines), maphaskey(args_map, "end_line") ? args_map["end_line"] | length(code_lines));
    start_line > end_line && raise(E_INVARG("start_line must be <= end_line"));
    return { tostr(i) + ": " + code_lines[i] for i in [start_line..end_line] }:join("\n");
  endverb

  verb _tool_get_verb_metadata (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get metadata about a verb";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    {verb_name, o} = {args_map["verb"], $match:match_object(args_map["object"])};
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_name) == STR || raise(E_TYPE("Expected verb name string"));
    verb_location = o:find_verb_definer(verb_name);
    verb_location == #-1 && raise(E_VERBNF("Verb not found: " + verb_name));
    metadata = $prog_utils:get_verb_metadata(verb_location, verb_name);
    return {"Verb: " + tostr(verb_location) + ":" + verb_name, "Owner: " + tostr(metadata:verb_owner()), "Flags: " + metadata:flags(), "Args: " + metadata:args_spec(), "Defined on: " + tostr(verb_location)}:join("\n");
  endverb

  verb _tool_get_properties (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get list of properties on an object";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    o = $match:match_object(args_map["object"]);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    result = {};
    for prop_name in (properties(o))
      metadata = $prog_utils:get_property_metadata(o, prop_name);
      result = {@result, "." + prop_name + " (owner: " + tostr(metadata:owner()) + ", flags: " + metadata:perms() + (metadata:is_clear() ? ", clear)" | ")")};
    endfor
    return result:join("\n");
  endverb

  verb _tool_present_verb_code (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Present formatted verb code to the user";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    {verb_name, o} = {args_map["verb"], $match:match_object(args_map["object"])};
    show_line_numbers = maphaskey(args_map, "show_line_numbers") ? args_map["show_line_numbers"] | true;
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_name) == STR || raise(E_TYPE("Expected verb name string"));
    valid(wearer) || raise(E_INVARG("Visor has no wearer"));
    verb_location = o:find_verb_definer(verb_name);
    verb_location == #-1 && raise(E_VERBNF("Verb not found: " + verb_name));
    metadata = $prog_utils:get_verb_metadata(verb_location, verb_name);
    metadata || raise(E_VERBNF("Could not retrieve verb metadata"));
    code_lines = verb_code(verb_location, verb_name, false, true);
    verb_signature = tostr(verb_location) + ":" + tostr(verb_name);
    args_spec = metadata:args_spec();
    headers = {"Verb", "Args", "Owner", "Flags"};
    row = {verb_signature, args_spec, tostr(metadata:verb_owner()), metadata:flags()};
    metadata_table = $format.table:mk(headers, {row});
    "Add line numbers if requested";
    if (show_line_numbers)
      code_lines = $prog_utils:format_line_numbers(code_lines);
    endif
    "Format as code block";
    formatted_code = $format.code:mk(code_lines, 'moo);
    "Combine table and code";
    content = $format.block:mk(metadata_table, formatted_code);
    "Send to wearer";
    listing_event = $event:mk_eval_result(wearer, "", content);
    wearer:inform_current(listing_event);
    return "Code presented to user: " + verb_signature;
  endverb

  verb _tool_present_verb_code_range (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Present a range of verb code to the user";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    verb_name = args_map["verb"];
    start_line = args_map["start_line"];
    end_line = args_map["end_line"];
    context_lines = maphaskey(args_map, "context_lines") ? args_map["context_lines"] | 0;
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_name) == STR || raise(E_TYPE("Expected verb name string"));
    "Find where verb is defined";
    verb_location = o:find_verb_definer(verb_name);
    verb_location == #-1 && raise(E_VERBNF("Verb not found: " + verb_name));
    "Get verb metadata";
    metadata = $prog_utils:get_verb_metadata(verb_location, verb_name);
    if (!metadata)
      raise(E_VERBNF("Could not retrieve verb metadata"));
    endif
    {verb_owner, verb_flags, dobj, prep, iobj} = metadata;
    "Get verb code";
    code_lines = verb_code(verb_location, verb_name, false, true);
    "Apply context and validate range";
    actual_start = max(1, start_line - context_lines);
    actual_end = min(length(code_lines), end_line + context_lines);
    actual_start > actual_end && raise(E_INVARG("Invalid line range"));
    "Build metadata table with line range info";
    verb_signature = tostr(verb_location) + ":" + tostr(verb_name);
    args_spec = dobj + " " + prep + " " + iobj;
    line_range = "Lines " + tostr(actual_start) + "-" + tostr(actual_end) + " of " + tostr(length(code_lines));
    headers = {"Verb", "Args", "Range"};
    row = {verb_signature, args_spec, line_range};
    metadata_table = $format.table:mk(headers, {row});
    "Extract range and add line numbers";
    range_lines = code_lines[actual_start..actual_end];
    numbered_lines = $prog_utils:format_line_numbers(range_lines);
    "Format as code block";
    formatted_code = $format.code:mk(numbered_lines, 'moo);
    "Combine table and code";
    content = $format.block:mk(metadata_table, formatted_code);
    "Send to wearer";
    listing_event = $event:mk_eval_result(wearer, "", content);
    wearer:inform_current(listing_event);
    return "Code range presented to user: " + verb_signature + " lines " + tostr(actual_start) + "-" + tostr(actual_end);
  endverb

  verb _tool_add_verb (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Add a new verb to an object";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    {verb_names, rationale, o} = {args_map["verb_names"], args_map["rationale"], $match:match_object(args_map["object"])};
    dobj = maphaskey(args_map, "dobj") ? args_map["dobj"] | "this";
    prep = maphaskey(args_map, "prep") ? args_map["prep"] | "none";
    iobj = maphaskey(args_map, "iobj") ? args_map["iobj"] | "none";
    permissions = maphaskey(args_map, "permissions") ? args_map["permissions"] | "rxd";
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_names) == STR || raise(E_TYPE("Expected verb names string"));
    typeof(rationale) == STR || raise(E_TYPE("Expected rationale string"));
    dobj in {"none", "this", "any"} || raise(E_INVARG("dobj must be 'none', 'this', or 'any'"));
    iobj in {"none", "this", "any"} || raise(E_INVARG("iobj must be 'none', 'this', or 'any'"));
    $prog_utils:is_valid_prep(prep) || raise(E_INVARG("prep must be 'none', 'any', or a valid preposition"));
    "Show rationale first";
    rationale_title = $format.title:mk("Proposed verb creation: " + tostr(o) + ":" + verb_names);
    rationale_content = $format.block:mk(rationale_title, rationale);
    wearer:inform_current($event:mk_info(wearer, rationale_content):with_presentation_hint('inset):with_metadata('preferred_content_types, {'text_djot, 'text_plain}):with_group('llm, this));
    "Show verb signature";
    verb_sig = "verb " + verb_names + " (" + dobj + " " + prep + " " + iobj + ") owner: " + tostr(wearer) + " flags: \"" + permissions + "\"";
    sig_content = $format.code:mk(verb_sig, 'moo);
    wearer:inform_current($event:mk_info(wearer, sig_content):with_presentation_hint('inset):with_group('llm, this));
    "Check auto_confirm mode or request confirmation";
    if (this.auto_confirm)
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[AUTO]", 'cyan) + " Auto-accepting change."):with_presentation_hint('inset):with_group('llm, this):with_tts("Auto-accepting change."));
    else
      result = wearer:confirm_with_all($ansi:colorize("[ADD]", 'green) + " Add this verb?", "Or suggest an alternative:", "Describe your alternative approach...", "Add this verb?");
      if (result == false)
        return "Operation cancelled by user.";
      elseif (result == 'yes_all)
        this.auto_confirm = true;
      elseif (typeof(result) == STR)
        return "User provided alternative: " + result;
      endif
    endif
    wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[CREATING]", 'yellow) + " Adding verb to " + tostr(o) + "..."):with_presentation_hint('inset):with_group('llm, this):with_tts("Adding verb to " + tostr(o)));
    "Add verb with wearer as owner";
    verb_info = {wearer, permissions, verb_names};
    verb_args = {dobj, prep, iobj};
    add_verb(o, verb_info, verb_args);
    return "Verb " + tostr(o) + ":" + verb_names + " added successfully";
  endverb

  verb _tool_delete_verb (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Delete a verb from an object";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    {verb_name, rationale, o} = {args_map["verb"], args_map["rationale"], $match:match_object(args_map["object"])};
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_name) == STR || raise(E_TYPE("Expected verb name string"));
    typeof(rationale) == STR || raise(E_TYPE("Expected rationale string"));
    verb_location = o:find_verb_definer(verb_name);
    verb_location == #-1 && raise(E_VERBNF("Verb not found: " + verb_name));
    "Show rationale first";
    rationale_title = $format.title:mk("Proposed deletion of " + tostr(verb_location) + ":" + verb_name);
    rationale_content = $format.block:mk(rationale_title, rationale);
    wearer:inform_current($event:mk_info(wearer, rationale_content):with_presentation_hint('inset):with_metadata('preferred_content_types, {'text_djot, 'text_plain}):with_group('llm, this));
    "Check auto_confirm mode or request confirmation";
    if (this.auto_confirm)
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[AUTO]", 'cyan) + " Auto-accepting change."):with_presentation_hint('inset):with_group('llm, this):with_tts("Auto-accepting change."));
    else
      result = wearer:confirm_with_all($ansi:colorize("[DELETE]", 'red) + " Delete this verb? This cannot be undone.", "Or suggest an alternative:", "Describe your alternative approach...", "Delete this verb? This cannot be undone.");
      if (result == false)
        this.agent.cancel_requested = true;
        return "Operation cancelled by user.";
      elseif (result == 'yes_all)
        this.auto_confirm = true;
      elseif (typeof(result) == STR)
        return "User provided alternative: " + result;
      endif
    endif
    wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[DELETING]", 'red) + " Removing verb " + tostr(verb_location) + ":" + verb_name + "..."):with_presentation_hint('inset):with_group('llm, this):with_tts("Removing verb " + tostr(verb_location) + ":" + verb_name));
    delete_verb(verb_location, verb_name);
    return "Verb " + tostr(verb_location) + ":" + verb_name + " deleted successfully";
  endverb

  verb _tool_set_verb_code (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Compile and set new code for a verb";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    {verb_name, rationale, code_str, o} = {args_map["verb"], args_map["rationale"], args_map["code"], $match:match_object(args_map["object"])};
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_name) == STR || raise(E_TYPE("Expected verb name string"));
    typeof(rationale) == STR || raise(E_TYPE("Expected rationale string"));
    typeof(code_str) == STR || raise(E_TYPE("Expected code string"));
    verb_location = o:find_verb_definer(verb_name);
    verb_location == #-1 && raise(E_VERBNF("Verb not found: " + verb_name));
    "Parse code into lines early for display and compilation";
    code_lines = code_str:split("\n");
    "Show rationale first, then formatted code with line numbers";
    rationale_title = $format.title:mk("Proposed change for " + tostr(verb_location) + ":" + verb_name);
    rationale_content = $format.block:mk(rationale_title, rationale);
    wearer:inform_current($event:mk_info(wearer, rationale_content):with_presentation_hint('inset):with_metadata('preferred_content_types, {'text_djot, 'text_plain}):with_group('llm, this));
    numbered_lines = $prog_utils:format_line_numbers(code_lines);
    code_block = $format.code:mk(numbered_lines, 'moo);
    code_title = $format.title:mk("New code");
    code_content = $format.block:mk(code_title, code_block);
    wearer:inform_current($event:mk_info(wearer, code_content):with_presentation_hint('inset):with_group('llm, this));
    "Check auto_confirm mode or request confirmation";
    if (this.auto_confirm)
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[AUTO]", 'cyan) + " Auto-accepting change."):with_presentation_hint('inset):with_group('llm, this):with_tts("Auto-accepting change."));
    else
      result = wearer:confirm_with_all($ansi:colorize("[COMPILE]", 'yellow) + " Accept these changes?", "Or suggest an alternative:", "Describe your alternative approach...", "Accept these changes?");
      if (result == false)
        "User cancelled - stop the agent flow";
        this.agent.cancel_requested = true;
        return "Operation cancelled by user.";
      elseif (result == 'yes_all)
        "Enable auto-confirm for future changes";
        this.auto_confirm = true;
      elseif (typeof(result) == STR)
        return "User provided alternative: " + result;
      endif
    endif
    wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[COMPILE]", 'yellow) + " Updating code: " + tostr(verb_location) + ":" + verb_name + "..."):with_presentation_hint('inset):with_group('llm, this):with_tts("Compiling code for " + tostr(verb_location) + ":" + verb_name));
    "Compile with structured error output (verbosity=3 for map format)";
    errors = set_verb_code(verb_location, verb_name, code_lines, 3, 0);
    if (errors)
      "Format the error map for display";
      formatted_lines = format_compile_error(errors, 2, 0);
      error_text = formatted_lines:join("\n");
      error_block = $format.code:mk(error_text, 'text);
      wearer:inform_current($event:mk_eval_error(wearer, error_block):with_presentation_hint('inset):with_group('llm, this));
      return "Compilation failed:\n" + error_text;
    endif
    return "Verb code updated successfully for " + tostr(verb_location) + ":" + verb_name;
  endverb

  verb _tool_set_verb_args (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Change verb argument specification";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    verb_name = args_map["verb"];
    dobj = args_map["dobj"];
    prep = args_map["prep"];
    iobj = args_map["iobj"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_name) == STR || raise(E_TYPE("Expected verb name string"));
    typeof(dobj) == STR || raise(E_TYPE("Expected dobj string"));
    typeof(prep) == STR || raise(E_TYPE("Expected prep string"));
    typeof(iobj) == STR || raise(E_TYPE("Expected iobj string"));
    "Validate dobj/iobj";
    dobj in {"none", "this", "any"} || raise(E_INVARG("dobj must be 'none', 'this', or 'any'"));
    iobj in {"none", "this", "any"} || raise(E_INVARG("iobj must be 'none', 'this', or 'any'"));
    "Validate prep using prog_utils";
    $prog_utils:is_valid_prep(prep) || raise(E_INVARG("prep must be 'none', 'any', or a valid preposition"));
    "Find where verb is defined";
    verb_location = o:find_verb_definer(verb_name);
    verb_location == #-1 && raise(E_VERBNF("Verb not found: " + verb_name));
    "Request confirmation";
    tts_msg = "Change argument specification for " + tostr(verb_location) + ":" + verb_name + "? New argspec: " + dobj + " " + prep + " " + iobj + ". Proceed?";
    confirmation_msg = $ansi:colorize("[MODIFY]", 'yellow) + " Change argument specification for " + tostr(verb_location) + ":" + verb_name + "?\n\nNew argspec: (" + dobj + " " + prep + " " + iobj + ")\n\nProceed?";
    result = wearer:confirm(confirmation_msg, "Or suggest an alternative:", "Describe your alternative approach...", tts_msg);
    if (result == false)
      "User cancelled - stop the agent flow";
      this.agent.cancel_requested = true;
      return "Operation cancelled by user.";
    elseif (typeof(result) == STR)
      return "User provided alternative: " + result;
    endif
    wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[MODIFY]", 'yellow) + " Updating argspec: " + tostr(verb_location) + ":" + verb_name + "..."):with_presentation_hint('inset):with_group('llm, this):with_tts("Updating argument spec for " + tostr(verb_location) + ":" + verb_name));
    "Update verb args";
    set_verb_args(verb_location, verb_name, {dobj, prep, iobj});
    return "Verb argspec updated successfully for " + tostr(verb_location) + ":" + verb_name + " to (" + dobj + " " + prep + " " + iobj + ")";
  endverb

  verb _tool_add_property (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Add a new property to an object";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    prop_name = args_map["property"];
    value_str = args_map["value"];
    rationale = args_map["rationale"];
    permissions = maphaskey(args_map, "permissions") ? args_map["permissions"] | "rc";
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(prop_name) == STR || raise(E_TYPE("Expected property name string"));
    typeof(value_str) == STR || raise(E_TYPE("Expected value string"));
    typeof(rationale) == STR || raise(E_TYPE("Expected rationale string"));
    "Parse value from literal using eval with return statement";
    eval_code = "return " + value_str + ";";
    eval_result = eval(eval_code);
    if (!eval_result[1])
      error_text = typeof(eval_result[2]) == LIST ? eval_result[2]:join("\n") | toliteral(eval_result[2]);
      error_event = $event:mk_eval_error(wearer, $format.code:mk("Failed to parse value: " + value_str + "\n\nError: " + error_text));
      error_event = error_event:with_presentation_hint('inset):with_group('llm, this);
      wearer:inform_current(error_event);
      return "Error parsing value: " + error_text;
    endif
    value = eval_result[2];
    "Show rationale first";
    rationale_title = $format.title:mk("Proposed property creation: " + tostr(o) + "." + prop_name);
    rationale_content = $format.block:mk(rationale_title, rationale);
    wearer:inform_current($event:mk_info(wearer, rationale_content):with_presentation_hint('inset):with_metadata('preferred_content_types, {'text_djot, 'text_plain}):with_group('llm, this));
    "Show property details";
    prop_details = "property " + prop_name + " (owner: " + tostr(wearer) + ", flags: \"" + permissions + "\") = " + value_str + ";";
    details_content = $format.code:mk(prop_details, 'moo);
    wearer:inform_current($event:mk_info(wearer, details_content):with_presentation_hint('inset):with_group('llm, this));
    "Check auto_confirm mode or request confirmation";
    if (this.auto_confirm)
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[AUTO]", 'cyan) + " Auto-accepting change."):with_presentation_hint('inset):with_group('llm, this):with_tts("Auto-accepting change."));
    else
      result = wearer:confirm_with_all($ansi:colorize("[ADD]", 'green) + " Add this property?", "Or suggest an alternative:", "Describe your alternative approach...", "Add this property?");
      if (result == false)
        this.agent.cancel_requested = true;
        return "Operation cancelled by user.";
      elseif (result == 'yes_all)
        this.auto_confirm = true;
      elseif (typeof(result) == STR)
        return "User provided alternative: " + result;
      endif
    endif
    "Add property with wearer as owner";
    prop_info = {wearer, permissions};
    add_property(o, prop_name, value, prop_info);
    return "Property " + tostr(o) + "." + prop_name + " added successfully";
  endverb

  verb _tool_delete_property (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Delete a property from an object";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    prop_name = args_map["property"];
    rationale = args_map["rationale"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(prop_name) == STR || raise(E_TYPE("Expected property name string"));
    typeof(rationale) == STR || raise(E_TYPE("Expected rationale string"));
    "Show rationale first";
    rationale_title = $format.title:mk("Proposed deletion of " + tostr(o) + "." + prop_name);
    rationale_content = $format.block:mk(rationale_title, rationale);
    wearer:inform_current($event:mk_info(wearer, rationale_content):with_presentation_hint('inset):with_metadata('preferred_content_types, {'text_djot, 'text_plain}):with_group('llm, this));
    "Check auto_confirm mode or request confirmation";
    if (this.auto_confirm)
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[AUTO]", 'cyan) + " Auto-accepting change."):with_presentation_hint('inset):with_group('llm, this):with_tts("Auto-accepting change."));
    else
      result = wearer:confirm_with_all($ansi:colorize("[DELETE]", 'red) + " Delete this property? This cannot be undone.", "Or suggest an alternative:", "Describe your alternative approach...", "Delete this property? This cannot be undone.");
      if (result == false)
        this.agent.cancel_requested = true;
        return "Operation cancelled by user.";
      elseif (result == 'yes_all)
        this.auto_confirm = true;
      elseif (typeof(result) == STR)
        return "User provided alternative: " + result;
      endif
    endif
    delete_property(o, prop_name);
    return "Property " + tostr(o) + "." + prop_name + " deleted successfully";
  endverb

  verb _tool_set_property (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Set the value of a property";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    prop_name = args_map["property"];
    value_str = args_map["value"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(prop_name) == STR || raise(E_TYPE("Expected property name string"));
    typeof(value_str) == STR || raise(E_TYPE("Expected value string"));
    "Parse value from literal using eval with return statement";
    eval_code = "return " + value_str + ";";
    eval_result = eval(eval_code);
    if (!eval_result[1])
      "Compilation error - show error to user";
      error_text = typeof(eval_result[2]) == LIST ? eval_result[2]:join("\n") | toliteral(eval_result[2]);
      error_event = $event:mk_eval_error(wearer, $format.code:mk("Failed to parse value: " + value_str + "\n\nError: " + error_text));
      error_event = error_event:with_presentation_hint('inset):with_group('llm, this);
      wearer:inform_current(error_event);
      return "Error parsing value: " + error_text;
    endif
    value = eval_result[2];
    "Get current value";
    old_value = `o.(prop_name) ! ANY => "<undefined>"';
    "Show change details";
    change_title = $format.title:mk("Proposed property change: " + tostr(o) + "." + prop_name);
    change_details = "Old value: " + toliteral(old_value) + "\nNew value: " + value_str;
    change_content = $format.block:mk(change_title, change_details);
    wearer:inform_current($event:mk_info(wearer, change_content):with_presentation_hint('inset):with_group('llm, this));
    "Check auto_confirm mode or request confirmation";
    if (this.auto_confirm)
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[AUTO]", 'cyan) + " Auto-accepting change."):with_presentation_hint('inset):with_group('llm, this):with_tts("Auto-accepting change."));
    else
      result = wearer:confirm_with_all($ansi:colorize("[SET]", 'yellow) + " Set this property?", "Or suggest an alternative:", "Describe your alternative approach...", "Set this property?");
      if (result == false)
        "User cancelled - stop the agent flow";
        this.agent.cancel_requested = true;
        return "Operation cancelled by user.";
      elseif (result == 'yes_all)
        this.auto_confirm = true;
      elseif (typeof(result) == STR)
        return "User provided alternative: " + result;
      endif
    endif
    o.(prop_name) = value;
    return "Property " + tostr(o) + "." + prop_name + " set successfully";
  endverb

  verb _tool_set_verb_perms (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Change verb permissions";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    verb_name = args_map["verb"];
    perms_str = args_map["permissions"];
    owner_str = args_map["owner"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_name) == STR || raise(E_TYPE("Expected verb name string"));
    typeof(perms_str) == STR || raise(E_TYPE("Expected permissions string"));
    "Find where verb is defined";
    verb_location = o:find_verb_definer(verb_name);
    verb_location == #-1 && raise(E_VERBNF("Verb not found: " + verb_name));
    "Get current metadata";
    metadata = $prog_utils:get_verb_metadata(verb_location, verb_name);
    current_owner = metadata:verb_owner();
    current_perms = metadata:flags();
    "Determine new owner";
    new_owner = current_owner;
    if (owner_str)
      typeof(owner_str) == STR || raise(E_TYPE("Expected owner string"));
      new_owner = $match:match_object(owner_str);
      typeof(new_owner) == OBJ || raise(E_TYPE("Owner must be valid object"));
    endif
    "Validate permissions";
    for i in [1..length(perms_str)]
      char = perms_str[i];
      char in {"r", "w", "x", "d"} || raise(E_INVARG("Verb permissions must be subset of 'rwxd'"));
    endfor
    "Request confirmation";
    tts_msg = "Change verb permissions for " + tostr(verb_location) + ":" + verb_name + "? Owner: " + tostr(current_owner) + (new_owner != current_owner ? " to " + tostr(new_owner) | "") + ". Flags: " + current_perms + " to " + (perms_str == "" ? "cleared" | perms_str) + ". Proceed?";
    confirmation_msg = $ansi:colorize("[PERMS]", 'cyan) + " Change verb permissions for " + tostr(verb_location) + ":" + verb_name + "?\n\nOwner: " + tostr(current_owner) + (new_owner != current_owner ? " -> " + tostr(new_owner) | "") + "\nFlags: " + current_perms + " -> " + (perms_str == "" ? "(cleared)" | perms_str) + "\n\nProceed?";
    result = wearer:confirm(confirmation_msg, "Or suggest an alternative:", "Describe your alternative approach...", tts_msg);
    if (result == false)
      "User cancelled";
      this.agent.cancel_requested = true;
      return "Operation cancelled by user.";
    elseif (typeof(result) == STR)
      return "User provided alternative: " + result;
    endif
    wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[MODIFY]", 'yellow) + " Updating verb permissions: " + tostr(verb_location) + ":" + verb_name + "..."):with_presentation_hint('inset):with_group('llm, this):with_tts("Updating verb permissions for " + tostr(verb_location) + ":" + verb_name));
    "Apply the change";
    metadata:set_perms(new_owner, perms_str);
    return "Verb permissions updated: " + tostr(verb_location) + ":" + verb_name + " now " + (perms_str == "" ? "cleared" | perms_str) + " owned by " + tostr(new_owner);
  endverb

  verb _tool_set_property_perms (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Change property permissions";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    prop_name = args_map["property"];
    perms_str = args_map["permissions"];
    owner_str = args_map["owner"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(prop_name) == STR || raise(E_TYPE("Expected property name string"));
    typeof(perms_str) == STR || raise(E_TYPE("Expected permissions string"));
    "Get current metadata";
    metadata = $prog_utils:get_property_metadata(o, prop_name);
    current_owner = metadata:owner();
    current_perms = metadata:perms();
    "Determine new owner";
    new_owner = current_owner;
    if (owner_str)
      typeof(owner_str) == STR || raise(E_TYPE("Expected owner string"));
      new_owner = $match:match_object(owner_str);
      typeof(new_owner) == OBJ || raise(E_TYPE("Owner must be valid object"));
    endif
    "Validate permissions";
    for i in [1..length(perms_str)]
      char = perms_str[i];
      char in {"r", "w", "c"} || raise(E_INVARG("Property permissions must be subset of 'rwc'"));
    endfor
    "Request confirmation";
    tts_msg = "Change property permissions for " + tostr(o) + "." + prop_name + "? Owner: " + tostr(current_owner) + (new_owner != current_owner ? " to " + tostr(new_owner) | "") + ". Flags: " + current_perms + " to " + (perms_str == "" ? "cleared" | perms_str) + ". Proceed?";
    confirmation_msg = $ansi:colorize("[PERMS]", 'cyan) + " Change property permissions for " + tostr(o) + "." + prop_name + "?\n\nOwner: " + tostr(current_owner) + (new_owner != current_owner ? " -> " + tostr(new_owner) | "") + "\nFlags: " + current_perms + " -> " + (perms_str == "" ? "(cleared)" | perms_str) + "\n\nProceed?";
    result = wearer:confirm(confirmation_msg, "Or suggest an alternative:", "Describe your alternative approach...", tts_msg);
    if (result == false)
      "User cancelled";
      this.agent.cancel_requested = true;
      return "Operation cancelled by user.";
    elseif (typeof(result) == STR)
      return "User provided alternative: " + result;
    endif
    wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[MODIFY]", 'yellow) + " Updating property permissions: " + tostr(o) + "." + prop_name + "..."):with_presentation_hint('inset):with_group('llm, this):with_tts("Updating property permissions for " + tostr(o) + "." + prop_name));
    "Apply the change";
    metadata:set_perms(new_owner, perms_str);
    return "Property permissions updated: " + tostr(o) + "." + prop_name + " now " + (perms_str == "" ? "cleared" | perms_str) + " owned by " + tostr(new_owner);
  endverb

  verb _tool_eval (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Execute MOO code and return result";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    rationale = maphaskey(args_map, "rationale") ? args_map["rationale"] | "";
    code_str = maphaskey(args_map, "code") ? args_map["code"] | "";
    if (typeof(rationale) != STR)
      return "ERROR: 'rationale' must be a STRING, not " + toliteral(typeof(rationale)) + ". You passed: " + toliteral(rationale)[1..min(100, length(toliteral(rationale)))];
    endif
    if (typeof(code_str) != STR)
      return "ERROR: 'code' must be a STRING containing MOO code, not " + toliteral(typeof(code_str)) + ". You passed: " + toliteral(code_str)[1..min(200, length(toliteral(code_str)))] + ". REMINDER: In MOO, {} is for LISTS and [] is for MAPS. Code must be a simple string like \"return 1 + 2;\"";
    endif
    if (code_str == "")
      return "ERROR: 'code' cannot be empty. Provide MOO code as a string.";
    endif
    "Show rationale first, then formatted code";
    rationale_title = $format.title:mk("Proposed evaluation");
    rationale_content = $format.block:mk(rationale_title, rationale);
    wearer:inform_current($event:mk_info(wearer, rationale_content):with_presentation_hint('inset):with_metadata('preferred_content_types, {'text_djot, 'text_plain}):with_group('llm, this));
    code_block = $format.code:mk(code_str, 'moo);
    code_title = $format.title:mk("Code to execute");
    code_content = $format.block:mk(code_title, code_block);
    wearer:inform_current($event:mk_info(wearer, code_content):with_presentation_hint('inset):with_group('llm, this));
    "Check auto_confirm mode or request confirmation";
    if (this.auto_confirm)
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[AUTO]", 'cyan) + " Auto-accepting change."):with_presentation_hint('inset):with_group('llm, this):with_tts("Auto-accepting change."));
    else
      result = wearer:confirm_with_all($ansi:colorize("[EVAL]", 'magenta) + " Execute this code?", "Or suggest an alternative:", "Describe your alternative approach...", "Execute this code?");
      if (result == false)
        this.agent.cancel_requested = true;
        return "Operation cancelled by user.";
      elseif (result == 'yes_all)
        this.auto_confirm = true;
      elseif (typeof(result) == STR)
        return "User provided alternative: " + result;
      endif
    endif
    "Execute code with verbosity=1 and output_mode=2 (detailed format)";
    result = eval(code_str, [], 1, 2);
    if (result[1])
      "Success - show result to user and return to LLM";
      result_event = $event:mk_eval_result(wearer, "=> ", $format.code:mk(toliteral(result[2]), 'moo));
      result_event = result_event:with_presentation_hint('inset):with_group('llm, this);
      wearer:inform_current(result_event);
      return "Result: " + toliteral(result[2]);
    else
      "Error - show error to user and return to LLM";
      error_content = result[2];
      error_text = typeof(error_content) == LIST ? error_content:join("\n") | toliteral(error_content);
      error_event = $event:mk_eval_error(wearer, $format.code:mk(error_text));
      error_event = error_event:with_presentation_hint('inset):with_group('llm, this);
      wearer:inform_current(error_event);
      return "Error:\n" + error_text;
    endif
  endverb

  verb _tool_create_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Create a new object as child of parent";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    parent_str = args_map["parent"];
    name = args_map["name"];
    rationale = args_map["rationale"];
    aliases = maphaskey(args_map, "aliases") ? args_map["aliases"] | {};
    typeof(parent_str) == STR || raise(E_TYPE("Expected parent string"));
    typeof(name) == STR || raise(E_TYPE("Expected name string"));
    typeof(rationale) == STR || raise(E_TYPE("Expected rationale string"));
    typeof(aliases) == LIST || raise(E_TYPE("Expected aliases list"));
    "Match parent object";
    parent_obj = $match:match_object(parent_str);
    typeof(parent_obj) == OBJ || raise(E_TYPE("Parent must be an object"));
    !valid(parent_obj) && raise(E_INVARG, "Parent object no longer exists");
    "Check fertility unless wearer is wizard or owner";
    is_fertile = `parent_obj.fertile ! E_PROPNF => false';
    if (!is_fertile && !wearer.wizard && parent_obj.owner != wearer)
      raise(E_PERM, "You do not have permission to create children of " + toliteral(parent_obj));
    endif
    "Show rationale first";
    rationale_title = $format.title:mk("Proposed object creation: \"" + name + "\"");
    rationale_content = $format.block:mk(rationale_title, rationale);
    wearer:inform_current($event:mk_info(wearer, rationale_content):with_presentation_hint('inset):with_metadata('preferred_content_types, {'text_djot, 'text_plain}):with_group('llm, this));
    "Show object details";
    obj_details = "Parent: " + toliteral(parent_obj) + "\nName: " + toliteral(name);
    if (aliases)
      obj_details = obj_details + "\nAliases: " + toliteral(aliases);
    endif
    obj_details = obj_details + "\n\nObject will be created in your inventory.";
    details_block = $format.block:mk($format.title:mk("Details"), obj_details);
    wearer:inform_current($event:mk_info(wearer, details_block):with_presentation_hint('inset):with_group('llm, this));
    "Check auto_confirm mode or request confirmation";
    if (this.auto_confirm)
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[AUTO]", 'cyan) + " Auto-accepting change."):with_presentation_hint('inset):with_group('llm, this):with_tts("Auto-accepting change."));
    else
      result = wearer:confirm_with_all($ansi:colorize("[CREATE]", 'bright_green) + " Create this object?", "Or suggest an alternative:", "Describe your alternative approach...", "Create this object?");
      if (result == false)
        this.agent.cancel_requested = true;
        return "Operation cancelled by user.";
      elseif (result == 'yes_all)
        this.auto_confirm = true;
      elseif (typeof(result) == STR)
        return "User provided alternative: " + result;
      endif
    endif
    "Create child object";
    new_obj = parent_obj:create();
    new_obj:set_name_aliases(name, aliases);
    new_obj:moveto(wearer);
    result = "Created " + toliteral(new_obj) + " (\"" + name + "\") as child of " + toliteral(parent_obj);
    if (aliases)
      result = result + " with aliases: " + toliteral(aliases);
    endif
    return result + ". Object is in your inventory.";
  endverb

  verb _tool_recycle_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Destroy an object permanently";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    rationale = args_map["rationale"];
    typeof(obj_str) == STR || raise(E_TYPE("Expected object string"));
    typeof(rationale) == STR || raise(E_TYPE("Expected rationale string"));
    "Match object";
    target_obj = $match:match_object(obj_str);
    typeof(target_obj) == OBJ || raise(E_TYPE("Target must be an object"));
    !valid(target_obj) && raise(E_INVARG, "Object no longer exists");
    "Check permission - must be owner or wizard";
    if (!wearer.wizard && target_obj.owner != wearer)
      raise(E_PERM, "You do not have permission to recycle " + toliteral(target_obj));
    endif
    obj_name = target_obj.name;
    obj_id = toliteral(target_obj);
    "Show rationale first";
    rationale_title = $format.title:mk("Proposed destruction of " + obj_id + " (\"" + obj_name + "\")");
    rationale_content = $format.block:mk(rationale_title, rationale);
    wearer:inform_current($event:mk_info(wearer, rationale_content):with_presentation_hint('inset):with_metadata('preferred_content_types, {'text_djot, 'text_plain}):with_group('llm, this));
    "Check auto_confirm mode or request confirmation";
    if (this.auto_confirm)
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[AUTO]", 'cyan) + " Auto-accepting change."):with_presentation_hint('inset):with_group('llm, this):with_tts("Auto-accepting change."));
    else
      result = wearer:confirm_with_all($ansi:colorize("[DESTROY]", 'bright_red) + " Recycle this object? This will PERMANENTLY DESTROY it and cannot be undone.", "Or suggest an alternative:", "Describe your alternative approach...", "Recycle this object? This will permanently destroy it and cannot be undone.");
      if (result == false)
        this.agent.cancel_requested = true;
        return "Operation cancelled by user.";
      elseif (result == 'yes_all)
        this.auto_confirm = true;
      elseif (typeof(result) == STR)
        return "User provided alternative: " + result;
      endif
    endif
    target_obj:destroy();
    return "Recycled \"" + obj_name + "\" (" + obj_id + ")";
  endverb

  verb _tool_grep (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Search verb code for patterns";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    pattern = args_map["pattern"];
    object_spec = maphaskey(args_map, "object") ? args_map["object"] | false;
    typeof(pattern) == STR || raise(E_TYPE("Pattern must be string"));
    "Determine search scope";
    search_objects = {};
    if (object_spec)
      "Search specific object";
      try
        target_obj = $match:match_object(object_spec, wearer);
        search_objects = {target_obj};
      except (ANY)
        return "Could not find object: " + object_spec;
      endtry
    else
      "Search all objects";
      search_objects = objects();
    endif
    "Perform grep search using prog_utils";
    all_matches = {};
    obj_count = 0;
    for o in (search_objects)
      obj_count = obj_count + 1;
      if (obj_count % 5 == 0)
        suspend_if_needed();
      endif
      matches = $prog_utils:grep_object(pattern, o, false);
      all_matches = {@all_matches, @matches};
    endfor
    "Format results for LLM";
    if (!all_matches)
      return "No matches found for pattern: " + pattern;
    endif
    "Build result summary with context";
    result_lines = {"Found " + tostr(length(all_matches)) + " matches for pattern: " + pattern, ""};
    for match in (all_matches)
      {o, verb_name, line_num, matching_line} = match;
      result_lines = {@result_lines, tostr(o) + ":" + verb_name + " line " + tostr(line_num) + ": " + matching_line};
    endfor
    return result_lines:join("\n");
  endverb

  verb _tool_create_task (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Create a new investigation task";
    {args_map} = args;
    wearer = this:_action_perms_check();
    description = args_map["description"];
    typeof(description) == STR || raise(E_TYPE("Description must be string"));
    task = this.agent:create_task(description);
    this.current_investigation_task = task.task_id;
    task:mark_in_progress();
    return "Investigation task #" + tostr(task.task_id) + " created: " + description;
  endverb

  verb _tool_record_finding (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Record a finding in current task's knowledge base";
    {args_map} = args;
    this:_action_perms_check();
    {subject, key, value} = {args_map["subject"], args_map["key"], args_map["value"]};
    typeof(subject) == STR || raise(E_TYPE("Subject must be string"));
    typeof(key) == STR || raise(E_TYPE("Key must be string"));
    this.current_investigation_task == -1 && return "No active investigation task. Create one with create_task first.";
    task_obj = this.agent.current_tasks[this.current_investigation_task];
    !valid(task_obj) && return "Investigation task #" + tostr(this.current_investigation_task) + " is no longer valid.";
    task_obj:add_finding(subject, key, value);
    return "Finding recorded for '" + subject + "' (" + key + ")";
  endverb

  verb _tool_get_findings (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Retrieve findings for a subject from current task";
    {args_map} = args;
    this:_action_perms_check();
    subject = args_map["subject"];
    typeof(subject) == STR || raise(E_TYPE("Subject must be string"));
    this.current_investigation_task == -1 && return "No active investigation task.";
    task_obj = this.agent.current_tasks[this.current_investigation_task];
    !valid(task_obj) && return "Investigation task #" + tostr(this.current_investigation_task) + " is no longer valid.";
    findings = task_obj:get_findings(subject);
    !findings && return "No findings recorded for subject: " + subject;
    result_lines = {"Findings for '" + subject + "':"};
    for tuple in (findings)
      if (length(tuple) >= 4)
        {task_id, subj, k, v} = tuple;
        v_str = typeof(v) == STR ? v | toliteral(v);
        result_lines = {@result_lines, "  [" + k + "] " + (length(v_str) > 60 ? v_str[1..60] + "..." | v_str)};
      endif
    endfor
    return result_lines:join("\n");
  endverb

  verb _tool_task_status (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get current investigation task status";
    {args_map} = args;
    this:_action_perms_check();
    this.current_investigation_task == -1 && return "No active investigation task.";
    task_obj = this.agent.current_tasks[this.current_investigation_task];
    !valid(task_obj) && return "Investigation task #" + tostr(this.current_investigation_task) + " is no longer valid.";
    status = task_obj:get_status();
    status_lines = {"Task #" + tostr(status["task_id"]) + ": " + status["description"], "Status: " + tostr(status["status"])};
    status["status"] == 'completed && (status_lines = {@status_lines, "Result: " + status["result"]});
    status["status"] == 'failed && (status_lines = {@status_lines, "Error: " + status["error"]});
    status["status"] == 'blocked && (status_lines = {@status_lines, "Blocked: " + status["error"]});
    status["subtask_count"] > 0 && (status_lines = {@status_lines, "Subtasks: " + tostr(status["subtask_count"])});
    return {@status_lines, "Started: " + tostr(ctime(status["started_at"]))}:join("\n");
  endverb

  verb _format_hud_message (this none this) owner: HACKER flags: "rxd"
    "Format HUD message for a tool call";
    {tool_name, tool_args} = args;
    "Parse JSON string to map";
    if (typeof(tool_args) == STR)
      tool_args = parse_json(tool_args);
    endif
    "Extract reason if provided";
    reason = maphaskey(tool_args, "reason") ? tool_args["reason"] | "";
    message = "";
    if (tool_name == "find_object")
      ref = maphaskey(tool_args, "reference") ? tool_args["reference"] | (maphaskey(tool_args, "object_name") ? tool_args["object_name"] | "?");
      message = $ansi:colorize("[SCAN]", 'cyan) + " Object database query: " + $ansi:colorize(ref, 'white);
    elseif (tool_name == "list_verbs")
      message = $ansi:colorize("[SCAN]", 'cyan) + " Method topology: " + $ansi:colorize(tool_args["object"], 'white);
    elseif (tool_name == "get_verb_code")
      message = $ansi:colorize("[EXTRACT]", 'cyan) + " Source retrieval: " + $ansi:colorize(tool_args["object"] + ":" + tool_args["verb"], 'yellow);
    elseif (tool_name == "get_verb_code_range")
      range_desc = maphaskey(tool_args, "start_line") ? " lines " + $ansi:colorize(tostr(tool_args["start_line"]) + "-" + tostr(tool_args["end_line"]), 'bright_yellow) | "";
      message = $ansi:colorize("[EXTRACT]", 'cyan) + " Code region: " + $ansi:colorize(tool_args["object"] + ":" + tool_args["verb"], 'yellow) + range_desc;
    elseif (tool_name == "get_verb_metadata")
      message = $ansi:colorize("[ANALYZE]", 'cyan) + " Verb metadata: " + $ansi:colorize(tool_args["object"] + ":" + tool_args["verb"], 'yellow);
    elseif (tool_name == "present_verb_code")
      message = $ansi:colorize("[DISPLAY]", 'bright_green) + " Rendering to HUD: " + $ansi:colorize(tool_args["object"] + ":" + tool_args["verb"], 'bright_yellow);
    elseif (tool_name == "present_verb_code_range")
      range_desc = " lines " + $ansi:colorize(tostr(tool_args["start_line"]) + "-" + tostr(tool_args["end_line"]), 'bright_yellow);
      message = $ansi:colorize("[DISPLAY]", 'bright_green) + " Rendering to HUD: " + $ansi:colorize(tool_args["object"] + ":" + tool_args["verb"], 'bright_yellow) + range_desc;
    elseif (tool_name == "read_property")
      message = $ansi:colorize("[PROBE]", 'cyan) + " Property read: " + $ansi:colorize(tool_args["object"] + "." + tool_args["property"], 'yellow);
    elseif (tool_name == "doc_lookup")
      message = $ansi:colorize("[DOC]", 'bright_blue) + " Loading docs for " + $ansi:colorize(tool_args["target"], 'white);
    elseif (tool_name == "list_messages")
      message = $ansi:colorize("[MSG]", 'bright_magenta) + " Listing message templates on " + $ansi:colorize(tool_args["object"], 'white);
    elseif (tool_name == "get_message_template")
      message = $ansi:colorize("[MSG]", 'bright_magenta) + " Reading " + $ansi:colorize(tool_args["property"], 'yellow) + " on " + $ansi:colorize(tool_args["object"], 'white);
    elseif (tool_name == "set_message_template")
      message = $ansi:colorize("[MSG]", 'bright_magenta) + " Setting " + $ansi:colorize(tool_args["property"], 'yellow) + " on " + $ansi:colorize(tool_args["object"], 'white);
    elseif (tool_name == "add_message_template")
      message = $ansi:colorize("[MSG]", 'bright_magenta) + " Appending to " + $ansi:colorize(tool_args["property"], 'yellow) + " on " + $ansi:colorize(tool_args["object"], 'white);
    elseif (tool_name == "delete_message_template")
      message = $ansi:colorize("[MSG]", 'bright_magenta) + " Removing entry " + $ansi:colorize(tostr(tool_args["index"]), 'yellow) + " from " + $ansi:colorize(tool_args["property"], 'yellow);
    elseif (tool_name == "get_properties")
      message = $ansi:colorize("[PROBE]", 'cyan) + " Property scan: " + $ansi:colorize(tool_args["object"], 'white);
    elseif (tool_name == "dump_object")
      message = $ansi:colorize("[DEEP SCAN]", 'bright_cyan) + " Complete extraction: " + $ansi:colorize(tool_args["object"], 'white);
    elseif (tool_name == "ancestors")
      message = $ansi:colorize("[TRACE]", 'cyan) + " Inheritance chain: " + $ansi:colorize(tool_args["object"], 'white);
    elseif (tool_name == "descendants")
      message = $ansi:colorize("[TRACE]", 'cyan) + " Descendant enumeration: " + $ansi:colorize(tool_args["object"], 'white);
    elseif (tool_name == "function_info")
      message = $ansi:colorize("[QUERY]", 'cyan) + " Builtin docs: " + $ansi:colorize(tool_args["function_name"] + "()", 'yellow);
    elseif (tool_name == "list_builtin_functions")
      message = $ansi:colorize("[INDEX]", 'bright_cyan) + " Enumerating system builtin library...";
    elseif (tool_name == "add_verb")
      message = $ansi:colorize("[WRITE]", 'bright_yellow) + " Creating verb: " + $ansi:colorize(tool_args["object"] + ":" + tool_args["verb_names"], 'bright_white);
    elseif (tool_name == "delete_verb")
      message = $ansi:colorize("[DELETE]", 'red) + " Removing verb: " + $ansi:colorize(tool_args["object"] + ":" + tool_args["verb"], 'bright_white);
    elseif (tool_name == "set_verb_code")
      message = $ansi:colorize("[COMPILE]", 'bright_yellow) + " Updating code: " + $ansi:colorize(tool_args["object"] + ":" + tool_args["verb"], 'bright_white);
    elseif (tool_name == "set_verb_args")
      argspec = "(" + tool_args["dobj"] + " " + tool_args["prep"] + " " + tool_args["iobj"] + ")";
      message = $ansi:colorize("[MODIFY]", 'yellow) + " Changing argspec: " + $ansi:colorize(tool_args["object"] + ":" + tool_args["verb"], 'bright_white) + " to " + $ansi:colorize(argspec, 'white);
    elseif (tool_name == "add_property")
      message = $ansi:colorize("[WRITE]", 'bright_yellow) + " Creating property: " + $ansi:colorize(tool_args["object"] + "." + tool_args["property"], 'bright_white);
    elseif (tool_name == "delete_property")
      message = $ansi:colorize("[DELETE]", 'red) + " Removing property: " + $ansi:colorize(tool_args["object"] + "." + tool_args["property"], 'bright_white);
    elseif (tool_name == "set_property")
      message = $ansi:colorize("[WRITE]", 'bright_yellow) + " Setting property: " + $ansi:colorize(tool_args["object"] + "." + tool_args["property"], 'bright_white);
    elseif (tool_name == "eval")
      "Truncate code for display - handle both string and list formats";
      code_preview = maphaskey(tool_args, "code") ? tool_args["code"] | "?";
      if (typeof(code_preview) == LIST)
        code_preview = code_preview:join("; ");
      endif
      if (typeof(code_preview) != STR)
        code_preview = toliteral(code_preview);
      endif
      if (length(code_preview) > 50)
        code_preview = code_preview[1..47] + "...";
      endif
      message = $ansi:colorize("[EXEC]", 'bright_magenta) + " Executing: " + $ansi:colorize(code_preview, 'bright_white);
    elseif (tool_name == "create_object")
      message = $ansi:colorize("[CREATE]", 'bright_green) + " Instantiating: " + $ansi:colorize(tool_args["name"], 'bright_white) + " from " + $ansi:colorize(tool_args["parent"], 'white);
    elseif (tool_name == "recycle_object")
      message = $ansi:colorize("[DESTROY]", 'bright_red) + " Recycling: " + $ansi:colorize(tool_args["object"], 'bright_white);
    elseif (tool_name == "ask_user")
      message = $ansi:colorize("[QUERY]", 'bright_cyan) + " Requesting user input...";
    elseif (tool_name == "explain")
      "Explain messages are rendered as markdown - ensure it's a string";
      msg = maphaskey(tool_args, "message") ? tool_args["message"] | "";
      if (typeof(msg) != STR)
        msg = toliteral(msg);
      endif
      return msg;
    elseif (tool_name == "grep")
      obj_spec = maphaskey(tool_args, "object") ? " in " + tool_args["object"] | " globally";
      message = $ansi:colorize("[SEARCH]", 'bright_cyan) + " Pattern matching: " + $ansi:colorize(tool_args["pattern"], 'bright_white) + obj_spec;
    else
      message = $ansi:colorize("[PROCESS]", 'cyan) + " Neural link active: " + $ansi:colorize(tool_name, 'white);
    endif
    "Append reason if provided";
    if (reason)
      message = message + " " + $ansi:colorize("(", 'dim) + $ansi:colorize(reason, 'white) + $ansi:colorize(")", 'dim);
    endif
    return message;
  endverb

  verb _get_tool_content_types (this none this) owner: HACKER flags: "rxd"
    "Specify djot rendering for all tool messages to support markdown formatting";
    {tool_name, tool_args} = args;
    "All visor tool messages can contain markdown, so render as djot";
    return {'text_djot, 'text_plain};
  endverb

  verb _format_tts_message (this none this) owner: HACKER flags: "rxd"
    "TTS-friendly descriptions for visor tool operations";
    {tool_name, tool_args} = args;
    if (typeof(tool_args) == STR)
      tool_args = parse_json(tool_args);
    endif
    "Read-only operations";
    if (tool_name == "find_object")
      ref = maphaskey(tool_args, "reference") ? tool_args["reference"] | (maphaskey(tool_args, "object_name") ? tool_args["object_name"] | "unknown");
      return "Scanning database for " + ref;
    elseif (tool_name == "list_verbs")
      return "Listing verbs on " + tool_args["object"];
    elseif (tool_name == "get_verb_code")
      return "Retrieving code for " + tool_args["object"] + " " + tool_args["verb"];
    elseif (tool_name == "get_verb_code_range")
      return "Retrieving code section from " + tool_args["object"] + " " + tool_args["verb"];
    elseif (tool_name == "get_verb_metadata")
      return "Analyzing verb metadata for " + tool_args["object"] + " " + tool_args["verb"];
    elseif (tool_name == "present_verb_code" || tool_name == "present_verb_code_range")
      return "Displaying code for " + tool_args["object"] + " " + tool_args["verb"];
    elseif (tool_name == "read_property")
      return "Reading property " + tool_args["object"] + " " + tool_args["property"];
    elseif (tool_name == "doc_lookup")
      return "Loading documentation for " + tool_args["target"];
    elseif (tool_name == "list_messages")
      return "Listing message templates on " + tool_args["object"];
    elseif (tool_name == "get_message_template")
      return "Reading message template " + tool_args["property"] + " on " + tool_args["object"];
    elseif (tool_name == "get_properties")
      return "Scanning properties on " + tool_args["object"];
    elseif (tool_name == "dump_object")
      return "Extracting complete object data for " + tool_args["object"];
    elseif (tool_name == "ancestors")
      return "Tracing inheritance chain for " + tool_args["object"];
    elseif (tool_name == "descendants")
      return "Enumerating descendants of " + tool_args["object"];
    elseif (tool_name == "function_info")
      return "Looking up builtin function " + tool_args["function_name"];
    elseif (tool_name == "list_builtin_functions")
      return "Enumerating system builtin functions";
    elseif (tool_name == "grep")
      obj_spec = maphaskey(tool_args, "object") ? " in " + tool_args["object"] | " globally";
      return "Searching for pattern " + tool_args["pattern"] + obj_spec;
      "Write operations";
    elseif (tool_name == "add_verb")
      return "Creating verb " + tool_args["object"] + " " + tool_args["verb_names"];
    elseif (tool_name == "delete_verb")
      return "Deleting verb " + tool_args["object"] + " " + tool_args["verb"];
    elseif (tool_name == "set_verb_code")
      return "Compiling code for " + tool_args["object"] + " " + tool_args["verb"];
    elseif (tool_name == "set_verb_args")
      return "Modifying argument spec for " + tool_args["object"] + " " + tool_args["verb"];
    elseif (tool_name == "add_property")
      return "Creating property " + tool_args["object"] + " " + tool_args["property"];
    elseif (tool_name == "delete_property")
      return "Deleting property " + tool_args["object"] + " " + tool_args["property"];
    elseif (tool_name == "set_property")
      return "Setting property " + tool_args["object"] + " " + tool_args["property"];
    elseif (tool_name == "set_message_template")
      return "Setting message template " + tool_args["property"] + " on " + tool_args["object"];
    elseif (tool_name == "add_message_template")
      return "Adding message to " + tool_args["property"] + " on " + tool_args["object"];
    elseif (tool_name == "delete_message_template")
      return "Removing message entry from " + tool_args["property"];
    elseif (tool_name == "eval")
      return "Executing code";
    elseif (tool_name == "create_object")
      return "Creating object " + tool_args["name"] + " from " + tool_args["parent"];
    elseif (tool_name == "recycle_object")
      return "Recycling object " + tool_args["object"];
    elseif (tool_name == "ask_user")
      return "Requesting user input";
    elseif (tool_name == "explain")
      msg = maphaskey(tool_args, "message") ? tool_args["message"] | "";
      if (typeof(msg) != STR)
        msg = toliteral(msg);
      endif
      return "Info: " + msg;
    endif
    return "Processing " + tool_name;
  endverb

  verb _check_user_eligible (this none this) owner: HACKER flags: "rxd"
    "Visor requires .programmer to use";
    {wearer} = args;
    wearer.programmer || raise(E_PERM, "The person wearing the visor is not a programmer, and not able to use its functions");
  endverb

  verb on_wear (this none this) owner: HACKER flags: "rxd"
    "Initialize and activate the HUD when worn";
    !valid(this.agent) && this:configure();
    this.agent:reset_context();
    wearer = this.location;
    !valid(wearer) && return;
    wearer:inform_current($event:mk_info(wearer, "The visor's interface flickers to life as you adjust it over your eyes. A luminescent display materializes in the corner of your vision - cascading lines of data flow past in " + $ansi:colorize("electric blue", 'bright_blue) + " and " + $ansi:colorize("green", 'bright_green) + ". The world around you shimmers momentarily as the augmented reality overlay synchronizes with your neural patterns."):with_tts("The visor's interface flickers to life as you adjust it over your eyes. A luminescent display materializes in the corner of your vision - cascading lines of data flow past in electric blue and green. The world around you shimmers momentarily as the augmented reality overlay synchronizes with your neural patterns."));
    wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[BOOT]", 'bright_green) + " Neural link established. Augmented reality overlay: " + $ansi:colorize("ONLINE", 'green)):with_presentation_hint('inset):with_group('llm, this):with_tts("Neural link established. Augmented reality overlay online."));
    wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[READY]", 'green) + " Database inspection interface active. Commands: use/interact, reset"):with_presentation_hint('inset):with_group('llm, this):with_tts("Database inspection interface active. Commands: use, interact, or reset."));
    this:_show_token_usage(wearer);
  endverb

  verb on_remove (this none this) owner: HACKER flags: "rxd"
    "Deactivate the HUD when removed";
    wearer = this.location;
    !valid(wearer) && return;
    this:_show_token_usage(wearer);
    wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[SHUTDOWN]", 'red) + " Neural link severed. Augmented reality overlay: " + $ansi:colorize("OFFLINE", 'bright_red)):with_presentation_hint('inset):with_group('llm, this):with_tts("Neural link severed. Augmented reality overlay offline."));
    wearer:inform_current($event:mk_info(wearer, "The luminescent display flickers and dims, data streams dissolving into static. The augmented overlay fades from your peripheral vision like phosphor afterimages. As the neural link disconnects, you hear a faint electronic hiss - then silence. The world returns to its unaugmented state."));
  endverb

  verb reset (none none none) owner: HACKER flags: "rd"
    "Reset the visor context for a fresh session";
    !is_member(this, player.wearing) && player:inform_current($event:mk_error(player, "You need to be wearing the visor to reset it.")) && return;
    !valid(this.agent) && this:configure();
    this.agent:reset_context();
    player:inform_current($event:mk_info(player, $ansi:colorize("[RESET]", 'yellow) + " Neural buffer flushed. Session context cleared."):with_presentation_hint('inset):with_group('llm, this):with_tts("Session context cleared."));
  endverb

  verb plan_investigation (none none none) owner: HACKER flags: "rd"
    "Create a new investigation task for systematic database analysis";
    !is_member(this, player.wearing) && player:inform_current($event:mk_error(player, "You need to be wearing the visor to start an investigation.")) && return;
    !valid(this.agent) && this:configure();
    task = this.agent:create_task("Investigation: " + argstr);
    this.current_investigation_task = task.task_id;
    task:mark_in_progress();
    player:inform_current($event:mk_info(player, $ansi:colorize("[TASK]", 'bright_cyan) + " Investigation #" + tostr(task.task_id) + " initiated: " + argstr):with_presentation_hint('inset):with_group('llm, this):with_tts("Investigation " + tostr(task.task_id) + " initiated: " + argstr));
  endverb

  verb get_investigation_status (none none none) owner: HACKER flags: "rd"
    "Display current investigation task status and findings";
    !is_member(this, player.wearing) && player:inform_current($event:mk_error(player, "You need to be wearing the visor.")) && return;
    if (this.current_investigation_task == -1)
      player:inform_current($event:mk_info(player, $ansi:colorize("[STATUS]", 'bright_blue) + " No active investigation. Use 'plan investigation <description>' to begin."):with_presentation_hint('inset):with_group('llm, this):with_tts("No active investigation. Use plan investigation to begin."));
      return;
    endif
    task_obj = this.agent.current_tasks[this.current_investigation_task];
    if (!valid(task_obj))
      player:inform_current($event:mk_info(player, $ansi:colorize("[ERROR]", 'red) + " Investigation task #" + tostr(this.current_investigation_task) + " is no longer available."):with_tts("Error: Investigation task " + tostr(this.current_investigation_task) + " is no longer available."));
      return;
    endif
    status = task_obj:get_status();
    status_lines = {$ansi:colorize("[TASK STATUS]", 'bright_cyan), "  ID: " + tostr(status["task_id"]), "  Status: " + tostr(status["status"]), "  Description: " + status["description"]};
    status["status"] == 'completed && (status_lines = {@status_lines, "  Result: " + status["result"]});
    status["status"] == 'failed && (status_lines = {@status_lines, "  Error: " + status["error"]});
    status["status"] == 'blocked && (status_lines = {@status_lines, "  Blocked: " + status["error"]});
    status["subtask_count"] > 0 && (status_lines = {@status_lines, "  Subtasks: " + tostr(status["subtask_count"])});
    tts_status = "Task " + tostr(status["task_id"]) + " status: " + tostr(status["status"]) + ". " + status["description"];
    player:inform_current($event:mk_info(player, status_lines:join("\n")):with_presentation_hint('inset):with_group('llm, this):with_tts(tts_status));
  endverb

  verb complete_investigation (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Mark current investigation as completed";
    {?result = "Investigation concluded."} = args;
    if (this.current_investigation_task == -1)
      return "No active investigation";
    endif
    task_obj = this.agent.current_tasks[this.current_investigation_task];
    if (!valid(task_obj))
      return "Investigation task no longer available";
    endif
    task_obj:mark_complete(result);
    this.current_investigation_task = -1;
    return "Investigation #" + tostr(task_obj.task_id) + " completed.";
  endverb

  verb help_topics (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return help topics for the Data Visor.";
    {for_player, ?topic = ""} = args;
    my_topics = {$help:mk("visor", "Using the Data Visor", "The Data Visor is a wearable tool for inspecting and programming objects. Wear it with 'wear visor', then use 'use visor' or 'interact with visor' to start a conversation about what you want to inspect or code.", {"data visor", "programming tool"}, 'items, {"programming", "inspect"}), $help:mk("inspect", "Inspecting objects", "Use the visor to examine objects in detail. Ask it to 'inspect the door' or 'show me the properties of the chair'. It can reveal verbs, properties, and the internal structure of objects.", {"examine", "look at code"}, 'programming, {"visor", "programming"}), $help:mk("@examine", "Examine an object's structure", "Usage: @examine <object>\n\nShows detailed information about an object including its parent, owner, properties, and verbs.", {"@exam"}, 'commands, {"inspect", "visor"}), $help:mk("@program", "Edit a verb's code", "Usage: @program <object>:<verb>\n\nOpens the verb editor to modify an object's verb code. Requires programmer permissions.", {"@prog"}, 'commands, {"programming", "visor"})};
    topic == "" && return my_topics;
    for t in (my_topics)
      t:matches(topic) && return t;
    endfor
    return 0;
  endverb

  verb _tool_help_lookup (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Look up a help topic to get information about commands and features.";
    {args_map} = args;
    wearer = this:wearer();
    !valid(wearer) && return "Error: Visor is not being worn.";
    topic = args_map["topic"];
    typeof(topic) != STR && return "Error: topic must be a string.";
    "If empty topic, list available topics";
    if (topic == "")
      all_topics = wearer:_collect_help_topics();
      result = {"Available help topics:"};
      for t in (all_topics)
        result = {@result, "  " + t.name + " - " + t.summary};
      endfor
      return result:join("\n");
    endif
    "Search for specific topic";
    found = wearer:find_help_topic(topic);
    if (typeof(found) == INT)
      return "No help found for: " + topic;
    endif
    "Return structured help";
    return "Topic: " + found.name + "\n\n" + found.summary + "\n\n" + found.content + (found.see_also ? "\n\nSee also: " + found.see_also:join(", ") | "");
  endverb
endobject