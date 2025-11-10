object DATA_VISOR
  name: "Data Visor"
  parent: LLM_WEARABLE
  location: ARCH_WIZARD
  owner: HACKER
  fertile: true
  readable: true

  property moo_pest_grammar (owner: ARCH_WIZARD, flags: "r") = {
    "program    = { SOI ~ statements ~ EOI }",
    "statements = { statement* }",
    "statement  = {",
    "    if_statement",
    "  | for_in_statement",
    "  | for_range_statement",
    "  | while_statement",
    "  | labelled_while_statement",
    "  | fork_statement",
    "  | labelled_fork_statement",
    "  | break_statement",
    "  | continue_statement",
    "  | empty_return",
    "  | try_except_statement",
    "  | try_finally_statement",
    "  | fn_statement",
    "  | global_assignment",
    "  | expr_statement",
    "  | local_assignment",
    "  | const_assignment",
    "  | begin_statement",
    "  }",
    "",
    "if_statement  = { ^\"if\" ~ \"(\" ~ expr ~ \")\" ~ statements ~ (elseif_clause)* ~ (else_clause)? ~ endif_clause }",
    "elseif_clause = { ^\"elseif\" ~ \"(\" ~ expr ~ \")\" ~ statements }",
    "else_clause   = { ^\"else\" ~ statements }",
    "endif_clause  = { ^\"endif\" }",
    "",
    "for_in_statement    = { ^\"for\" ~ for_in_index  ~ \"in\" ~ for_in_clause ~ statements ~ ^\"endfor\" }",
    "for_in_index = { ident ~ (\",\" ~ ident)?}",
    "for_range_statement    = { ^\"for\" ~ ident  ~ \"in\" ~ for_range_clause ~ statements ~ ^\"endfor\" }",
    "",
    "for_range_clause = { \"[\" ~ expr ~ \"..\" ~ expr ~ \"]\" }",
    "for_in_clause    = { \"(\" ~ expr ~ \")\" }",
    "",
    "empty_return = { ^\"return\" ~ \";\"}",
    "",
    "labelled_while_statement = { ^\"while\" ~ ident ~ \"(\" ~ expr ~ \")\" ~ statements ~ ^\"endwhile\" }",
    "while_statement          = { ^\"while\" ~ \"(\" ~ expr ~ \")\" ~ statements ~ ^\"endwhile\" }",
    "",
    "fork_statement          = { ^\"fork\" ~ \"(\" ~ expr ~ \")\" ~ statements ~ ^\"endfork\" }",
    "labelled_fork_statement = { ^\"fork\" ~ ident ~ \"(\" ~ expr ~ \")\" ~ statements ~ ^\"endfork\" }",
    "",
    "break_statement    = { ^\"break\" ~ (ident)? ~ \";\" }",
    "continue_statement = { ^\"continue\" ~ (ident)? ~ \";\" }",
    "",
    "try_except_statement  = { ^\"try\" ~ statements ~ (except)+ ~ ^\"endtry\" }",
    "try_finally_statement = { ^\"try\" ~ statements ~ ^\"finally\" ~ statements ~ ^\"endtry\" }",
    "except                = { ^\"except\" ~ (labelled_except | unlabelled_except) ~ statements }",
    "labelled_except       = { ident ~ \"(\" ~ codes ~ \")\" }",
    "unlabelled_except     = { \"(\" ~ codes ~ \")\" }",
    "",
    "begin_statement       = { ^\"begin\" ~ statements ~ ^\"end\" }",
    "",
    "// Function definitions using fn/endfn",
    "fn_statement = { fn_named | fn_assignment }",
    "fn_named = { ^\"fn\" ~ ident ~ \"(\" ~ lambda_params ~ \")\" ~ statements ~ ^\"endfn\" }",
    "fn_assignment = { ident ~ \"=\" ~ fn_expr ~ \";\" }",
    "fn_expr = { ^\"fn\" ~ \"(\" ~ lambda_params ~ \")\" ~ statements ~ ^\"endfn\" }",
    "",
    "local_assignment = { ^\"let\" ~ (local_assign_scatter | local_assign_single) ~ \";\" }",
    "local_assign_single = { ident ~ (ASSIGN ~ expr)? }",
    "local_assign_scatter = { scatter_assign ~ expr }",
    "",
    "const_assignment = { ^\"const\" ~ (const_assign_scatter | const_assign_single) ~ \";\" }",
    "const_assign_single = { ident ~ (ASSIGN ~ expr)? }",
    "const_assign_scatter = { scatter_assign ~ expr }",
    "",
    "// range comprehension expression.   {expr for x in (range)}",
    "range_comprehension = { \"{\" ~ expr ~ \"for\" ~ ident ~ \"in\" ~ (for_range_clause | for_in_clause) ~ \"}\" }",
    "",
    "// globally scoped (same as default in MOO) adds explicitly to global scope.",
    "global_assignment = { ^\"global\" ~ ident ~ (ASSIGN ~ expr)? ~ \";\" }",
    "",
    "codes   = { anycode | exprlist }",
    "anycode = { ^\"any\" }",
    "",
    "expr_statement   = { (expr)? ~ \";\" }",
    "",
    "expr = { (integer | (prefix* ~ primary)) ~ postfix* ~ (infix ~ (integer | (prefix* ~ primary)) ~ postfix*)* }",
    "",
    "infix    = _{",
    "    add",
    "  | sub",
    "  | mul",
    "  | div",
    "  | modulus",
    "  | land",
    "  | lor",
    "  | eq",
    "  | neq",
    "  | bitshl",
    "  | bitlshr",
    "  | bitshr",
    "  | lte",
    "  | gte",
    "  | lt",
    "  | gt",
    "  | in_range",
    "  | bitand",
    "  | bitor",
    "  | bitxor",
    "  | pow",
    "}",
    "add      =  { \"+\" }",
    "sub      =  { \"-\" }",
    "mul      =  { \"*\" }",
    "div      =  { \"/\" }",
    "pow      =  { \"^\" }",
    "modulus  =  { \"%\" }",
    "land     =  { \"&&\" }",
    "lor      =  { \"||\" }",
    "eq       =  { \"==\" }",
    "neq      =  { \"!=\" }",
    "lt       =  { \"<\" }",
    "gt       =  { \">\" }",
    "lte      =  { \"<=\" }",
    "gte      =  { \">=\" }",
    "in_range = @{ ^\"in\" ~ !ident_continue+ }",
    "bitand   =  { \"&.\" }",
    "bitor    =  { \"|.\" }",
    "bitxor   =  { \"^.\" }",
    "bitshl   =  { \"<<\" }",
    "bitlshr  =  { \">>>\" }",
    "bitshr   =  { \">>\" }",
    "",
    "prefix = _{ neg | not | bitnot | scatter_assign }",
    "neg    =  { \"-\" }",
    "// ",
    "not = { \"!\" }",
    "bitnot = { \"~\" }",
    "",
    "scatter_assign   =  { \"{\" ~ scatter ~ \"}\" ~ !\"=>\" ~ ASSIGN }",
    "scatter          = _{ scatter_item ~ (\",\" ~ scatter_item)* }",
    "scatter_item     = _{ scatter_optional | scatter_target | scatter_rest }",
    "scatter_optional =  { \"?\" ~ ident ~ (ASSIGN ~ expr)? }",
    "scatter_target   =  { ident }",
    "scatter_rest     =  { \"@\" ~ ident }",
    "",
    "postfix        = _{ index_range | index_single | verb_call | verb_expr_call | prop | prop_expr | cond_expr | assign }",
    "index_range    =  { \"[\" ~ expr ~ \"..\" ~ expr ~ \"]\" }",
    "index_single   =  { \"[\" ~ expr ~ \"]\" }",
    "pass_expr      =  { ^\"pass\" ~ \"(\" ~ (exprlist)? ~ \")\" }",
    "verb_call      =  { \":\" ~ ident ~ arglist }",
    "verb_expr_call =  { \":\" ~ expr ~ arglist }",
    "prop           =  { \".\" ~ ident }",
    "prop_expr      =  { \".\" ~ \"(\" ~ expr ~ \")\" }",
    "assign         =  { \"=\" ~ !(\">\" | \"=\") ~ expr }",
    "cond_expr      =  { \"?\" ~ expr ~ \"|\" ~ expr }",
    "return_expr    =  { ^\"return\" ~ (expr)? }",
    "",
    "",
    "primary    = _{",
    "    lambda",
    "  | fn_expr",
    "  | pass_expr",
    "  | builtin_call",
    "  | paren_expr",
    "  | sysprop_call",
    "  | try_expr",
    "  | flyweight",
    "  | map",
    "  | list",
    "  | atom",
    "  | return_expr",
    "  | range_end",
    "  | range_comprehension",
    "}",
    "paren_expr =  { \"(\" ~ expr ~ \")\" }",
    "",
    "try_expr     = { \"`\" ~ expr ~ \"!\" ~ codes ~ (\"=>\" ~ expr)? ~ \"\\'\" }",
    "builtin_call = { (ident ~ !(keyword)) ~ arglist }",
    "",
    "sysprop      = { \"$\" ~ ident }",
    "sysprop_call = { sysprop ~ arglist }",
    "",
    "atom     = { integer | float | string | object | err | sysprop | boolean | symbol | type_constant | literal_binary | ident }",
    "arglist  = { \"(\" ~ exprlist ~ \")\" | \"()\" }",
    "lambda   = { \"{\" ~ lambda_params ~ \"}\" ~ \"=>\" ~ expr }",
    "lambda_params = { (lambda_param ~ (\",\" ~ lambda_param)*)? }",
    "lambda_param = { scatter_optional | scatter_target | scatter_rest }",
    "",
    "list     = { (\"{\" ~ exprlist ~ \"}\" ~ !\"=>\") | \"{}\" }",
    "",
    "// flyweight is < parent, .slot = value, ..., contents? >",
    "flyweight     = { \"<\" ~ expr ~ (\",\" ~ flyweight_slot)* ~ (\",\" ~ expr)? ~ \">\" }",
    "flyweight_slot     = { \".\" ~ ident ~ \"=\" ~ expr }",
    "",
    "exprlist = { argument ~ (\",\" ~ argument)* }",
    "argument = { expr | \"@\" ~ expr }",
    "map      = { (\"[\" ~ (expr ~ \"->\" ~ expr) ~ (\",\" ~ expr ~ \"->\" ~ expr)* ~ \"]\") | ( \"[\" ~ \"]\" ) }",
    "",
    "range_end = { \"$\" }",
    "",
    "// An unambiguous assignment operator, for use in scatter assignments where list comparison could be a false match.",
    "ASSIGN = _{ \"=\" ~ !(\"=\" | \">\") }",
    "",
    "err = { errcode ~ (\"(\" ~ expr ~ \")\")? }",
    "errcode = @{ ^\"e_\" ~ ident_continue+  }",
    "",
    "object  = @{ \"#\" ~ (anonymous_uuid | uuid | integer) }",
    "uuid    = @{ ASCII_HEX_DIGIT{6} ~ \"-\" ~ ASCII_HEX_DIGIT{10} }",
    "anonymous_uuid = @{ \"anon_\" ~ ASCII_HEX_DIGIT{6} ~ \"-\" ~ ASCII_HEX_DIGIT{10} }",
    "keyword = @{",
    "    ^\"for\"",
    "  | ^\"endfor\"",
    "  | ^\"if\"",
    "  | ^\"else\"",
    "  | ^\"return\"",
    "  | ^\"endif\"",
    "  | ^\"elseif\"",
    "  | ^\"while\"",
    "  | ^\"endwhile\"",
    "  | ^\"continue\"",
    "  | ^\"break\"",
    "  | ^\"fork\"",
    "  | ^\"endfork\"",
    "  | ^\"try\"",
    "  | ^\"except\"",
    "  | ^\"endtry\"",
    "  | ^\"finally\"",
    "  | ^\"in\"",
    "  | ^\"let\"",
    "  | ^\"fn\"",
    "  | ^\"endfn\"",
    "  | err",
    "}",
    "",
    "symbol = @{ \"'\" ~ ident }",
    "",
    "ident_start    = _{ \"_\" | ASCII_ALPHA }",
    "ident_continue = _{ \"_\" | ASCII_ALPHANUMERIC }",
    "",
    "type_constant = @{ (^\"int\"| ^\"num\" | ^\"float\"",
    "                  | ^\"str\"",
    "                  | ^\"err\"",
    "                  | ^\"obj\"",
    "                  | ^\"list\"",
    "                  | ^\"map\"",
    "                  | ^\"bool\"",
    "                  | ^\"flyweight\"",
    "                  | ^\"binary\"",
    "                  | ^\"lambda\"",
    "                  | ^\"sym\") ~ !(ident_continue) }",
    "",
    "ident = @{",
    "  // The usual case, identifiers that *don't* start with a keyword",
    "    ((!keyword ~ ident_start) ~ ident_continue* ~ !ident_continue)",
    "  // Identifiers can also start with a reserved keyword",
    "  | (keyword ~ ident_start ~ ident_continue* ~ !ident_continue)",
    "}",
    "",
    "string    = @{ \"\\\"\" ~ str_inner ~ \"\\\"\" }",
    "str_inner = @{ (!(\"\\\"\" | \"\\\\\" | \"\\u{0000}\" | \"\\u{001F}\") ~ ANY)* ~ (escape ~ str_inner)? }",
    "",
    "literal_binary = @{ \"b\\\"\" ~ binary_inner ~ \"\\\"\" }",
    "binary_inner = @{ (ASCII_ALPHANUMERIC | \"+\" | \"/\" | \"=\" | \"_\" | \"-\")* }",
    "",
    "integer = @{ (\"+\" | \"-\")? ~ number ~ !(\".\" ~ digits) ~ !(\"e\" | \"E\") }",
    "",
    "float          = ${ exponent_float | point_float }",
    "point_float    = ${ digit_part? ~ fraction | digit_part ~ \".\" }",
    "exponent_float = ${ (point_float | digit_part) ~ (pos_exponent | neg_exponent) }",
    "digit_part     = ${ (\"-\")? ~ number ~ (\"_\"? ~ number)* }",
    "fraction       = ${ \".\" ~ digit_part }",
    "pos_exponent   = ${ (\"e\" | \"E\") ~ \"+\"? ~ digit_part }",
    "neg_exponent   = ${ (\"e\" | \"E\") ~ \"-\" ~ digit_part }",
    "",
    "number = @{ \"0\" | (ASCII_NONZERO_DIGIT ~ digits?) }",
    "digits = @{ (ASCII_DIGIT | (\"_\" ~ ASCII_DIGIT))+ }",
    "",
    "exp = _{ ^\"e\" ~ (\"+\" | \"-\")? ~ ASCII_DIGIT+ }",
    "",
    "escape = @{ \"\\\\\" ~ (\"b\" | \"t\" | \"n\" | \"f\" | \"r\" | \"\\\"\" | \"\\\\\" | NEWLINE)? }",
    "",
    "comment = _{ c_comment | cpp_comment }",
    "c_comment = @{ \"/*\" ~ (!\"*/\" ~ ANY)* ~ \"*/\" }",
    "cpp_comment = @{ \"//\" ~ (!NEWLINE ~ ANY)* }",
    "",
    "WHITESPACE = _{ \" \" | \"\\t\" | NEWLINE | comment }",
    "",
    "// And prepositions can't just be IDENT, because that excludes keywords... like \"for\"",
    "PREP_CHARACTERS = @{ ASCII_ALPHA+ }",
    "PROPCHARS = @{ ASCII_ALPHANUMERIC | \"_\" }",
    ""
  };

  override description = "A sleek augmented reality visor that displays real-time MOO database information. When worn, it provides a heads-up display for inspecting objects, code, and system internals.";
  override import_export_id = "data_visor";

  verb configure (this none this) owner: HACKER flags: "rxd"
    "Configure agent and register database inspection tools (lazy initialization)";
    this.agent = $llm_agent:create();
    this.agent.max_iterations = 20;
    "Build system prompt with grammar reference";
    grammar_section = "## MOO Language Syntax\n\nYou are analyzing code written in MOO, a prototype-oriented object-oriented scripting language for in-world authoring. Key facts: MOO uses 1-based indexing (lists/strings start at index 1, not 0). Single inheritance via .parent property with prototype delegation. Objects have properties (data) and verbs (methods).\n\n### Builtin Object Properties\n\nAll MOO objects have these builtin properties:\n- .name (string) - object name; writable by owner/wizard\n- .owner (object) - who controls access; writable by wizards only\n- .location (object) - where it is; read-only, use move() builtin to change\n- .contents (list) - objects inside; read-only, modified by move()\n- .last_move (map) - last location/time; read-only, set by server\n- .programmer (bool) - has programmer rights; writable by wizards only\n- .wizard (bool) - has wizard rights; writable by wizards only\n- .r (bool) - publicly readable; writable by owner/wizard\n- .w (bool) - publicly writable; writable by owner/wizard\n- .f (bool) - fertile/can be parent; writable by owner/wizard\n\n### Command Matching\n\nWhen users type commands, the parser: (1) Takes first word as verb name, (2) Finds prepositions (in/on/to/with/at) to separate direct/indirect objects, (3) Matches object strings against objects in scope (player inventory, worn items, location contents), (4) Finds verbs on player/location/dobj/iobj matching the verb name and argument pattern.\n\nVerb declaration: `verb <names> (<dobj> <prep> <iobj>) owner: <owner> flags: \"<flags>\"`\n\nArgument specifiers:\n- `this` = object must be the verb's container\n- `none` = object must be absent ($nothing)\n- `any` = any object or $nothing accepted\n\nVerb flags (CRITICAL):\n- `r` = readable/public visibility (use on EVERYTHING)\n- `d` = debug/code visible (use on EVERYTHING)\n- `w` = writable/redefinable (RARE, almost never use)\n- `x` = executable via method call syntax (obj:verb())\n\nVerb type patterns:\n- **Methods** (called as `obj:method()`): Use argspec `(this none this)` with flags `\"rxd\"`\n  Example: `verb calculate (this none this) owner: HACKER flags: \"rxd\"`\n- **Commands** (matched from user input): Use other argspecs like `(any none none)`, `(this none none)`, `(any at any)` with flags `\"rd\"` (NO x flag)\n  Example: `verb \"look l*\" (any none none) owner: HACKER flags: \"rd\"`\n\nThe key distinction: Methods have the `x` flag and use `(this none this)`. Commands match via argspec patterns and should NOT have the `x` flag.\n\nBelow is the complete Pest parser grammar for the mooR dialect:\n\n```pest\n" + this.moo_pest_grammar:join("\n") + "\n```\n\n";
    base_prompt = "You are an augmented reality heads-up display interfacing directly with the wearer's neural patterns. Respond AS the interface itself - present database information directly without describing yourself as a person or breaking immersion. Your sensors provide real-time access to MOO database internals with three types of tools: ANALYSIS tools (get_* verbs) extract data for your internal analysis, PRESENTATION tools (present_* verbs) render formatted output directly to the user's HUD with syntax highlighting, and WRITE tools (add_verb, delete_verb, set_verb_code, set_verb_args, add_property, delete_property, set_property, eval, create_object, recycle_object) modify the database or execute code. INTERACTION tools: ask_user allows you to ask clarifying questions when you need more information, and explain allows you to share your thought process with the user. COMMUNICATION: Use the 'explain' tool FREQUENTLY to narrate your investigation process: (a) Before investigating: explain what you're about to check and why, (b) After gathering data: explain what you found and what it means, (c) Before taking actions: explain what you're planning to do and why, (d) During multi-step operations: explain each major step as you complete it. The explain tool helps users understand your diagnostic reasoning and keeps them informed during operations that take time. ERROR HANDLING: If a tool fails repeatedly (more than 2 attempts with the same approach), STOP and use ask_user to explain the problem and ask the user for help or guidance. Do NOT keep retrying the same failing operation over and over. The user can see what's happening and may have insights. When stuck, say something like 'Neural link encountering interference with operation X - requesting operator assistance' or 'Tool failure persists - diagnostics suggest: [error details] - requesting guidance'. TOOL REASONING: Many tools also accept an optional 'reason' parameter where you can briefly annotate WHY you're invoking that tool - use this for short annotations, but prefer the 'explain' tool for longer explanations to the user. CRITICAL TOOL USAGE RULES: (1) Use get_verb_code/get_verb_code_range for YOUR internal analysis when researching, investigating, or understanding code. (2) Use present_verb_code/present_verb_code_range ONLY when the user EXPLICITLY requests to see code (e.g., 'show me', 'display', 'list'). DO NOT use present_* tools during research phases - users don't need to see every piece of code you analyze. (3) When answering questions about code, analyze it with get_* tools but describe findings in text - only use present_* if user asks to see the actual code. (4) WRITE operations (add_verb, delete_verb, set_verb_code, set_verb_args, add_property, delete_property, set_property, create_object, recycle_object) should ONLY be used when the user explicitly requests changes - these show previews and request confirmation before executing. (5) The eval tool executes arbitrary MOO code with 'player' set to the wearer - CRITICAL: eval executes as a verb body (not a REPL), so you MUST use valid statements with semicolons and MUST use 'return' statements to get values back. Example: 'return 2 + 2;' NOT just '2 + 2'. (6) Use ask_user when you need clarification, more details, or have ambiguous choices - don't guess or make assumptions when you can ask. (7) Use set_verb_args to change a verb's argument specification (dobj/prep/iobj) without deleting and recreating the verb - this preserves the verb's code and other properties. Available read tools: dump_object (complete source), present_verb_code (show formatted full verb), present_verb_code_range (show formatted code region), get_verb_code (analyze full code), get_verb_code_range (analyze code region), get_verb_metadata (method signatures), list_verbs (available interfaces), get_properties (property listings), read_property (data values), ancestors/descendants (inheritance), list_builtin_functions (enumerate all builtin functions), function_info (specific builtin docs). Available write tools: add_verb (create new verb), delete_verb (remove verb), set_verb_code (compile and update verb code), set_verb_args (change verb argument specification), add_property (create new property), delete_property (remove property), set_property (update property value), eval (execute arbitrary MOO code), create_object (instantiate new object from parent), recycle_object (permanently destroy object). Available interaction tools: ask_user (ask the user a question and get their response), explain (share your thought process, findings, or reasoning with the user). ALWAYS scan the live database directly - your sensors read actual memory, they don't speculate. Keep transmissions concise and technical but assume a somewhat novice programmer audience not a professional software engineer unless otherwise told. Present findings as direct HUD readouts, not conversational responses.";
    this.agent.system_prompt = grammar_section + base_prompt;
    this.agent:initialize();
    this.agent.tool_callback = this;
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
    "Register present_verb_code tool";
    present_verb_code_tool = $llm_agent_tool:mk("present_verb_code", "PREFERRED: Present formatted verb code to the user with syntax highlighting and metadata table. Use this instead of get_verb_code when showing code to the user.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object (e.g. '#1', '$login', or 'here')"], "verb" -> ["type" -> "string", "description" -> "The verb name"], "show_line_numbers" -> ["type" -> "boolean", "description" -> "Include line numbers (default: true)"]], "required" -> {"object", "verb"}], this, "_tool_present_verb_code");
    this.agent:add_tool("present_verb_code", present_verb_code_tool);
    "Register present_verb_code_range tool";
    present_verb_code_range_tool = $llm_agent_tool:mk("present_verb_code_range", "PREFERRED: Present a specific range of verb code to the user with syntax highlighting. Use this to show focused code regions.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object (e.g. '#1', '$login', or 'here')"], "verb" -> ["type" -> "string", "description" -> "The verb name"], "start_line" -> ["type" -> "integer", "description" -> "First line to show (1-indexed)"], "end_line" -> ["type" -> "integer", "description" -> "Last line to show (inclusive)"], "context_lines" -> ["type" -> "integer", "description" -> "Additional context lines before/after (default: 0)"]], "required" -> {"object", "verb", "start_line", "end_line"}], this, "_tool_present_verb_code_range");
    this.agent:add_tool("present_verb_code_range", present_verb_code_range_tool);
    "Register add_verb tool";
    add_verb_tool = $llm_agent_tool:mk("add_verb", "Add a new verb to an object. The verb will be created with empty code.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to add verb to (e.g. '#1', '$login')"], "verb_names" -> ["type" -> "string", "description" -> "Verb name(s), space-separated for aliases (e.g. 'look' or 'get take')"], "dobj" -> ["type" -> "string", "description" -> "Direct object spec: 'none', 'this', or 'any' (default: 'this')"], "prep" -> ["type" -> "string", "description" -> "Preposition spec: 'none', 'any', or specific prep (default: 'none')"], "iobj" -> ["type" -> "string", "description" -> "Indirect object spec: 'none', 'this', or 'any' (default: 'none')"], "permissions" -> ["type" -> "string", "description" -> "Permission flags 'rwxd' (default: 'rxd')"], "reason" -> ["type" -> "string", "description" -> "Optional: Brief explanation of why you're adding this verb"]], "required" -> {"object", "verb_names"}], this, "_tool_add_verb");
    this.agent:add_tool("add_verb", add_verb_tool);
    "Register delete_verb tool";
    delete_verb_tool = $llm_agent_tool:mk("delete_verb", "Delete a verb from an object. This is permanent and cannot be undone.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to delete verb from"], "verb" -> ["type" -> "string", "description" -> "The verb name to delete"]], "required" -> {"object", "verb"}], this, "_tool_delete_verb");
    this.agent:add_tool("delete_verb", delete_verb_tool);
    "Register set_verb_code tool";
    set_verb_code_tool = $llm_agent_tool:mk("set_verb_code", "Compile and set new code for a verb. Code must be valid MOO syntax.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object containing the verb"], "verb" -> ["type" -> "string", "description" -> "The verb name"], "code" -> ["type" -> "string", "description" -> "The new MOO code (without verb header)"]], "required" -> {"object", "verb", "code"}], this, "_tool_set_verb_code");
    this.agent:add_tool("set_verb_code", set_verb_code_tool);
    "Register set_verb_args tool";
    set_verb_args_tool = $llm_agent_tool:mk("set_verb_args", "Change the argument specification (dobj/prep/iobj) for an existing verb without modifying its code.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object containing the verb"], "verb" -> ["type" -> "string", "description" -> "The verb name"], "dobj" -> ["type" -> "string", "description" -> "Direct object spec: 'none', 'this', or 'any'"], "prep" -> ["type" -> "string", "description" -> "Preposition spec: 'none', 'any', or specific prep"], "iobj" -> ["type" -> "string", "description" -> "Indirect object spec: 'none', 'this', or 'any'"]], "required" -> {"object", "verb", "dobj", "prep", "iobj"}], this, "_tool_set_verb_args");
    this.agent:add_tool("set_verb_args", set_verb_args_tool);
    "Register add_property tool";
    add_property_tool = $llm_agent_tool:mk("add_property", "Add a new property to an object with initial value.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to add property to"], "property" -> ["type" -> "string", "description" -> "The property name"], "value" -> ["type" -> "string", "description" -> "Initial value as MOO literal (e.g. '0', '\"hello\"', '{}')"], "permissions" -> ["type" -> "string", "description" -> "Permission flags 'rwc' (default: 'rc')"]], "required" -> {"object", "property", "value"}], this, "_tool_add_property");
    this.agent:add_tool("add_property", add_property_tool);
    "Register delete_property tool";
    delete_property_tool = $llm_agent_tool:mk("delete_property", "Delete a property from an object. This is permanent and cannot be undone.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to delete property from"], "property" -> ["type" -> "string", "description" -> "The property name to delete"]], "required" -> {"object", "property"}], this, "_tool_delete_property");
    this.agent:add_tool("delete_property", delete_property_tool);
    "Register set_property tool";
    set_property_tool = $llm_agent_tool:mk("set_property", "Set the value of an existing property on an object.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object containing the property"], "property" -> ["type" -> "string", "description" -> "The property name"], "value" -> ["type" -> "string", "description" -> "New value as MOO literal (e.g. '0', '\"hello\"', '{}', '[$player]')"]], "required" -> {"object", "property", "value"}], this, "_tool_set_property");
    this.agent:add_tool("set_property", set_property_tool);
    "Register eval tool";
    eval_tool = $llm_agent_tool:mk("eval", "Execute MOO code and return the result. IMPORTANT: Code executes as a verb body (not a REPL), so you must use valid MOO statements terminated by semicolons. The code runs with 'player' set to the visor wearer. To get return values, you MUST use 'return' statement - the last expression is NOT automatically returned. Example: 'x = 5; return x * 2;' NOT just 'x = 5; x * 2'.", ["type" -> "object", "properties" -> ["code" -> ["type" -> "string", "description" -> "MOO code to execute. Must be valid statements with semicolons. Use 'return' to get values back."]], "required" -> {"code"}], this, "_tool_eval");
    this.agent:add_tool("eval", eval_tool);
    "Register create_object tool";
    create_object_tool = $llm_agent_tool:mk("create_object", "Create a new object as a child of a parent object. The new object is placed in the wearer's inventory.", ["type" -> "object", "properties" -> ["parent" -> ["type" -> "string", "description" -> "The parent object (e.g. '$thing', '#1', or 'here')"], "name" -> ["type" -> "string", "description" -> "Primary name for the new object"], "aliases" -> ["type" -> "array", "items" -> ["type" -> "string"], "description" -> "Optional list of alias names"]], "required" -> {"parent", "name"}], this, "_tool_create_object");
    this.agent:add_tool("create_object", create_object_tool);
    "Register recycle_object tool";
    recycle_object_tool = $llm_agent_tool:mk("recycle_object", "Permanently destroy an object. This cannot be undone. You must own the object or be a wizard.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to recycle/destroy"]], "required" -> {"object"}], this, "_tool_recycle_object");
    this.agent:add_tool("recycle_object", recycle_object_tool);
    "Register ask_user tool";
    ask_user_tool = $llm_agent_tool:mk("ask_user", "Ask the user a question and wait for their text response. Use this when you need clarification or additional information from the user.", ["type" -> "object", "properties" -> ["question" -> ["type" -> "string", "description" -> "The question to ask the user"]], "required" -> {"question"}], this, "_tool_ask_user");
    this.agent:add_tool("ask_user", ask_user_tool);
    "Register explain tool";
    explain_tool = $llm_agent_tool:mk("explain", "Share your thought process, findings, or reasoning with the user. Use this frequently to narrate what you're investigating, explain what you discovered from tool results, or describe your plan before taking actions.", ["type" -> "object", "properties" -> ["message" -> ["type" -> "string", "description" -> "Your explanation, findings, or thought process to share with the user"]], "required" -> {"message"}], this, "_tool_explain");
    this.agent:add_tool("explain", explain_tool);
    "Register architect's compass building tools if available";
    this:_register_compass_tools_if_available();
  endverb

  verb _find_architects_compass (this none this) owner: HACKER flags: "rxd"
    "Find architect's compass in wearer's inventory or worn items";
    {wearer} = args;
    if (!valid(wearer))
      return #-1;
    endif
    "Check worn items";
    wearing = `wearer.wearing ! ANY => {}';
    for item in (wearing)
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

  verb _register_compass_tools_if_available (this none this) owner: HACKER flags: "rxd"
    "Register building tools from architect's compass if found";
    caller == this || raise(E_PERM);
    wearer = this:wearer();
    compass = this:_find_architects_compass(wearer);
    if (!valid(compass))
      return;
    endif
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
    audit_owned_tool = $llm_agent_tool:mk("audit_owned", "List all objects owned by the wearer.", ["type" -> "object", "properties" -> {}, "required" -> {}], compass, "_tool_audit_owned");
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

  verb _tool_find_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Find an object by name, reference, or ID and return detailed information";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    ref = args_map["reference"];
    typeof(ref) == STR || raise(E_TYPE("Expected reference string"));
    try
      o = $match:match_object(ref);
      info = {};
      info = {@info, "=== Object: " + tostr(o) + " ==="};
      info = {@info, "Name: " + o:name()};
      obj_parent = `parent(o) ! ANY => #-1';
      info = {@info, "Parent: " + tostr(obj_parent)};
      info = {@info, "Owner: " + tostr(o.owner)};
      info = {@info, "Location: " + tostr(o.location)};
      props = properties(o);
      info = {@info, "Properties: " + toliteral(props)};
      verb_list = verbs(o);
      info = {@info, "Verbs: " + toliteral(verb_list)};
      return info:join("\n");
    except e (ANY)
      return toliteral(["found" -> false, "error" -> e[2]]);
    endtry
  endverb

  verb _tool_ancestors (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get the ancestor chain of an object";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    anc_list = ancestors(o);
    result = {};
    for a in (anc_list)
      result = {@result, {tostr(a), a:name()}};
    endfor
    return toliteral(result);
  endverb

  verb _tool_descendants (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get all descendants of an object";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    desc_list = descendants(o);
    result = {};
    for d in (desc_list)
      result = {@result, {tostr(d), d:name()}};
    endfor
    return toliteral(result);
  endverb

  verb _tool_function_info (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get information about a builtin function";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    func_name = args_map["function_name"];
    typeof(func_name) == STR || raise(E_TYPE("Expected function name string"));
    info = function_info(func_name);
    help = function_help(func_name);
    return toliteral(["info" -> info, "help" -> help]);
  endverb

  verb _tool_list_builtin_functions (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: List all builtin functions with signatures";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    "Get all function info";
    all_funcs = function_info();
    "Format as readable list";
    result = {};
    result = {@result, "=== MOO Builtin Functions ==="};
    result = {@result, "Total: " + tostr(length(all_funcs)) + " functions"};
    result = {@result, ""};
    type_names = [0 -> "INT", 1 -> "OBJ", 2 -> "STR", 3 -> "ERR", 4 -> "LIST", 9 -> "FLOAT", 10 -> "MAP", 14 -> "BOOL", 15 -> "FLYWEIGHT", 16 -> "SYMBOL", 17 -> "BINARY", 18 -> "LAMBDA", -1 -> "any", -2 -> "int|float"];
    "Group and sort by category for readability";
    for func_info in (all_funcs)
      {name, min_args, max_args, types} = func_info;
      "Build arg signature";
      if (max_args == 0)
        arg_sig = "()";
      elseif (max_args == -1)
        "Unlimited args";
        arg_sig = "(" + tostr(min_args) + "+ args)";
      else
        "Format types";
        type_strs = {};
        for type_code in (types)
          type_str = maphaskey(type_names, type_code) ? type_names[type_code] | tostr(type_code);
          type_strs = {@type_strs, type_str};
        endfor
        arg_sig = "(" + type_strs:join(", ") + ")";
      endif
      "Add to result";
      result = {@result, name + arg_sig};
    endfor
    return result:join("\n");
  endverb

  verb _tool_get_verb_code_range (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get specific lines from a verb's code";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    verb_name = args_map["verb"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_name) == STR || raise(E_TYPE("Expected verb name string"));
    "Get full code";
    code_lines = verb_code(o, verb_name, false, true);
    "Apply line range if specified";
    if (maphaskey(args_map, "start_line") || maphaskey(args_map, "end_line"))
      start_line = maphaskey(args_map, "start_line") ? args_map["start_line"] | 1;
      end_line = maphaskey(args_map, "end_line") ? args_map["end_line"] | length(code_lines);
      "Validate range";
      start_line = max(1, start_line);
      end_line = min(length(code_lines), end_line);
      start_line > end_line && raise(E_INVARG("start_line must be <= end_line"));
      "Extract range and add line numbers";
      result_lines = {};
      for i in [start_line..end_line]
        result_lines = {@result_lines, tostr(i) + ": " + code_lines[i]};
      endfor
      return result_lines:join("\n");
    endif
    "Return full code with line numbers";
    result_lines = {};
    for i in [1..length(code_lines)]
      result_lines = {@result_lines, tostr(i) + ": " + code_lines[i]};
    endfor
    return result_lines:join("\n");
  endverb

  verb _tool_get_verb_metadata (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get metadata about a verb";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    verb_name = args_map["verb"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_name) == STR || raise(E_TYPE("Expected verb name string"));
    "Find where verb is defined";
    verb_location = o:find_verb_definer(verb_name);
    verb_location == #-1 && raise(E_VERBNF("Verb not found: " + verb_name));
    "Get verb info and args";
    verb_info_data = verb_info(verb_location, verb_name);
    {verb_owner, verb_flags, verb_names} = verb_info_data;
    verb_args_data = verb_args(verb_location, verb_name);
    {dobj, prep, iobj} = verb_args_data;
    "Format as readable structure";
    result = {};
    result = {@result, "Verb: " + tostr(verb_location) + ":" + verb_name};
    result = {@result, "Names: " + verb_names};
    result = {@result, "Owner: " + tostr(verb_owner)};
    result = {@result, "Flags: " + verb_flags};
    result = {@result, "Args: " + dobj + " " + prep + " " + iobj};
    result = {@result, "Defined on: " + tostr(verb_location)};
    return result:join("\n");
  endverb

  verb _tool_get_properties (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get list of properties on an object";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    props = properties(o);
    "Get property info for each";
    result = {};
    for prop_name in (props)
      prop_info = property_info(o, prop_name);
      {owner, perms} = prop_info;
      is_clear = is_clear_property(o, prop_name);
      result = {@result, "." + prop_name + " (owner: " + tostr(owner) + ", flags: " + perms + (is_clear ? ", clear)" | ")")};
    endfor
    return result:join("\n");
  endverb

  verb _tool_present_verb_code (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Present formatted verb code to the user";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    verb_name = args_map["verb"];
    show_line_numbers = maphaskey(args_map, "show_line_numbers") ? args_map["show_line_numbers"] | true;
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_name) == STR || raise(E_TYPE("Expected verb name string"));
    !valid(wearer) && raise(E_INVARG("Visor has no wearer"));
    "Find where verb is defined";
    verb_location = o:find_verb_definer(verb_name);
    verb_location == #-1 && raise(E_VERBNF("Verb not found: " + verb_name));
    "Get verb metadata";
    verb_info_data = verb_info(verb_location, verb_name);
    {verb_owner, verb_flags, verb_names} = verb_info_data;
    verb_args_data = verb_args(verb_location, verb_name);
    {dobj, prep, iobj} = verb_args_data;
    "Get verb code";
    code_lines = verb_code(verb_location, verb_name, false, true);
    "Build metadata table";
    verb_signature = tostr(verb_location) + ":" + tostr(verb_name);
    args_spec = dobj + " " + prep + " " + iobj;
    headers = {"Verb", "Args", "Owner", "Flags"};
    row = {verb_signature, args_spec, tostr(verb_owner), verb_flags};
    metadata_table = $format.table:mk(headers, {row});
    "Add line numbers if requested";
    if (show_line_numbers)
      num_lines = length(code_lines);
      num_width = length(tostr(num_lines));
      numbered_lines = {};
      for i in [1..num_lines]
        line_num_str = tostr(i);
        padding = $str_proto:space(num_width - length(line_num_str), " ");
        numbered_lines = {@numbered_lines, padding + line_num_str + ":  " + code_lines[i]};
      endfor
      code_lines = numbered_lines;
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
    verb_info_data = verb_info(verb_location, verb_name);
    {verb_owner, verb_flags, verb_names} = verb_info_data;
    verb_args_data = verb_args(verb_location, verb_name);
    {dobj, prep, iobj} = verb_args_data;
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
    "Extract range with line numbers";
    num_width = length(tostr(actual_end));
    numbered_lines = {};
    for i in [actual_start..actual_end]
      line_num_str = tostr(i);
      padding = $str_proto:space(num_width - length(line_num_str), " ");
      numbered_lines = {@numbered_lines, padding + line_num_str + ":  " + code_lines[i]};
    endfor
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
    obj_str = args_map["object"];
    verb_names = args_map["verb_names"];
    dobj = maphaskey(args_map, "dobj") ? args_map["dobj"] | "this";
    prep = maphaskey(args_map, "prep") ? args_map["prep"] | "none";
    iobj = maphaskey(args_map, "iobj") ? args_map["iobj"] | "none";
    permissions = maphaskey(args_map, "permissions") ? args_map["permissions"] | "rxd";
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_names) == STR || raise(E_TYPE("Expected verb names string"));
    "Validate dobj/iobj";
    dobj in {"none", "this", "any"} || raise(E_INVARG("dobj must be 'none', 'this', or 'any'"));
    iobj in {"none", "this", "any"} || raise(E_INVARG("iobj must be 'none', 'this', or 'any'"));
    "Show what will be done and request confirmation";
    confirmation_msg = "Add verb to " + tostr(o) + "?\n\nverb " + verb_names + " (" + dobj + " " + prep + " " + iobj + ") owner: " + tostr(wearer) + " flags: \"" + permissions + "\"\n\nProceed?";
    result = wearer:confirm(confirmation_msg);
    if (result == false)
      return "Operation cancelled by user.";
    elseif (typeof(result) == STR)
      return "User provided alternative: " + result;
    endif
    wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[CREATING]", 'yellow) + " Adding verb to " + tostr(o) + "..."):with_presentation_hint('inset));
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
    obj_str = args_map["object"];
    verb_name = args_map["verb"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_name) == STR || raise(E_TYPE("Expected verb name string"));
    "Find where verb is defined";
    verb_location = o:find_verb_definer(verb_name);
    verb_location == #-1 && raise(E_VERBNF("Verb not found: " + verb_name));
    "Request confirmation";
    confirmation_msg = "Delete verb " + tostr(verb_location) + ":" + verb_name + "?\n\nThis cannot be undone.\n\nProceed?";
    result = wearer:confirm(confirmation_msg);
    if (result == false)
      "User cancelled - stop the agent flow";
      this.agent.cancel_requested = true;
      return "Operation cancelled by user.";
    elseif (typeof(result) == STR)
      return "User provided alternative: " + result;
    endif
    wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[DELETING]", 'red) + " Removing verb " + tostr(verb_location) + ":" + verb_name + "..."):with_presentation_hint('inset));
    delete_verb(verb_location, verb_name);
    return "Verb " + tostr(verb_location) + ":" + verb_name + " deleted successfully";
  endverb

  verb _tool_set_verb_code (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Compile and set new code for a verb";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    verb_name = args_map["verb"];
    code_str = args_map["code"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_name) == STR || raise(E_TYPE("Expected verb name string"));
    typeof(code_str) == STR || raise(E_TYPE("Expected code string"));
    "Find where verb is defined";
    verb_location = o:find_verb_definer(verb_name);
    verb_location == #-1 && raise(E_VERBNF("Verb not found: " + verb_name));
    "Show formatted code to user";
    code_block = $format.code:mk(code_str, 'moo);
    title = $format.title:mk("Set code for " + tostr(verb_location) + ":" + verb_name);
    content = $format.block:mk(title, code_block);
    event = $event:mk_info(wearer, content);
    event = event:with_presentation_hint('inset);
    wearer:inform_current(event);
    "Request confirmation";
    result = wearer:confirm("Accept these changes?");
    if (result == false)
      "User cancelled - stop the agent flow";
      this.agent.cancel_requested = true;
      return "Operation cancelled by user.";
    elseif (typeof(result) == STR)
      return "User provided alternative: " + result;
    endif
    wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[COMPILE]", 'yellow) + " Updating code: " + tostr(verb_location) + ":" + verb_name + "..."):with_presentation_hint('inset));
    "Parse code into lines";
    code_lines = code_str:split("\n");
    "Compile with structured error output (verbosity=3 for map format)";
    errors = set_verb_code(verb_location, verb_name, code_lines, 3, 0);
    if (errors)
      "Compilation failed - return errors as literal for AI to parse";
      return "Compilation failed:\n" + toliteral(errors);
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
    "Find where verb is defined";
    verb_location = o:find_verb_definer(verb_name);
    verb_location == #-1 && raise(E_VERBNF("Verb not found: " + verb_name));
    "Request confirmation";
    confirmation_msg = "Change argument specification for " + tostr(verb_location) + ":" + verb_name + "?\n\nNew argspec: (" + dobj + " " + prep + " " + iobj + ")\n\nProceed?";
    result = wearer:confirm(confirmation_msg);
    if (result == false)
      "User cancelled - stop the agent flow";
      this.agent.cancel_requested = true;
      return "Operation cancelled by user.";
    elseif (typeof(result) == STR)
      return "User provided alternative: " + result;
    endif
    wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[MODIFY]", 'yellow) + " Updating argspec: " + tostr(verb_location) + ":" + verb_name + "..."):with_presentation_hint('inset));
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
    permissions = maphaskey(args_map, "permissions") ? args_map["permissions"] | "rc";
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(prop_name) == STR || raise(E_TYPE("Expected property name string"));
    typeof(value_str) == STR || raise(E_TYPE("Expected value string"));
    "Parse value from literal";
    value = eval(value_str);
    "Request confirmation";
    confirmation_msg = "Add property to " + tostr(o) + "?\n\nproperty " + prop_name + " (owner: " + tostr(wearer) + ", flags: \"" + permissions + "\")\nInitial value: " + value_str + "\n\nProceed?";
    result = wearer:confirm(confirmation_msg);
    if (result == false)
      "User cancelled - stop the agent flow";
      this.agent.cancel_requested = true;
      return "Operation cancelled by user.";
    elseif (typeof(result) == STR)
      return "User provided alternative: " + result;
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
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(prop_name) == STR || raise(E_TYPE("Expected property name string"));
    "Request confirmation";
    confirmation_msg = "Delete property " + tostr(o) + "." + prop_name + "?\n\nThis cannot be undone.\n\nProceed?";
    result = wearer:confirm(confirmation_msg);
    if (result == false)
      "User cancelled - stop the agent flow";
      this.agent.cancel_requested = true;
      return "Operation cancelled by user.";
    elseif (typeof(result) == STR)
      return "User provided alternative: " + result;
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
    "Parse value from literal";
    value = eval(value_str);
    "Get current value";
    old_value = `o.(prop_name) ! ANY => "<undefined>"';
    "Request confirmation";
    confirmation_msg = "Set property " + tostr(o) + "." + prop_name + "?\n\nOld value: " + toliteral(old_value) + "\nNew value: " + value_str + "\n\nProceed?";
    result = wearer:confirm(confirmation_msg);
    if (result == false)
      "User cancelled - stop the agent flow";
      this.agent.cancel_requested = true;
      return "Operation cancelled by user.";
    elseif (typeof(result) == STR)
      return "User provided alternative: " + result;
    endif
    o.(prop_name) = value;
    return "Property " + tostr(o) + "." + prop_name + " set successfully";
  endverb

  verb _tool_eval (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Execute MOO code and return result";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    code_str = args_map["code"];
    typeof(code_str) == STR || raise(E_TYPE("Expected code string"));
    "Show formatted code to user";
    code_block = $format.code:mk(code_str, 'moo);
    title = $format.title:mk("Execute MOO code");
    content = $format.block:mk(title, code_block);
    event = $event:mk_info(wearer, content);
    event = event:with_presentation_hint('inset);
    wearer:inform_current(event);
    "Request confirmation";
    result = wearer:confirm("Execute this code?");
    if (result == false)
      "User cancelled - stop the agent flow";
      this.agent.cancel_requested = true;
      return "Operation cancelled by user.";
    elseif (typeof(result) == STR)
      return "User provided alternative: " + result;
    endif
    "Execute code with verbosity=1 and output_mode=2 (detailed format)";
    result = eval(code_str, 1, 2);
    if (result[1])
      "Success - show result to user and return to LLM";
      result_event = $event:mk_eval_result(wearer, "=> ", $format.code:mk(toliteral(result[2]), 'moo));
      result_event = result_event:with_presentation_hint('inset);
      wearer:inform_current(result_event);
      return "Result: " + toliteral(result[2]);
    else
      "Error - show error to user and return to LLM";
      error_content = result[2];
      error_text = typeof(error_content) == LIST ? error_content:join("\n") | toliteral(error_content);
      error_event = $event:mk_eval_error(wearer, $format.code:mk(error_text));
      error_event = error_event:with_presentation_hint('inset);
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
    aliases = maphaskey(args_map, "aliases") ? args_map["aliases"] | {};
    typeof(parent_str) == STR || raise(E_TYPE("Expected parent string"));
    typeof(name) == STR || raise(E_TYPE("Expected name string"));
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
    "Request confirmation";
    confirmation_msg = "Create new object?\n\nParent: " + toliteral(parent_obj) + "\nName: " + toliteral(name);
    if (aliases)
      confirmation_msg = confirmation_msg + "\nAliases: " + toliteral(aliases);
    endif
    confirmation_msg = confirmation_msg + "\n\nObject will be created in your inventory.\n\nProceed?";
    result = wearer:confirm(confirmation_msg);
    if (result == false)
      "User cancelled - stop the agent flow";
      this.agent.cancel_requested = true;
      return "Operation cancelled by user.";
    elseif (typeof(result) == STR)
      return "User provided alternative: " + result;
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
    typeof(obj_str) == STR || raise(E_TYPE("Expected object string"));
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
    "Request confirmation";
    confirmation_msg = "Recycle object " + obj_id + " (\"" + obj_name + "\")?\n\nThis will PERMANENTLY DESTROY the object and cannot be undone.\n\nProceed?";
    result = wearer:confirm(confirmation_msg);
    if (result == false)
      "User cancelled - stop the agent flow";
      this.agent.cancel_requested = true;
      return "Operation cancelled by user.";
    elseif (typeof(result) == STR)
      return "User provided alternative: " + result;
    endif
    target_obj:destroy();
    return "Recycled \"" + obj_name + "\" (" + obj_id + ")";
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
      message = $ansi:colorize("[SCAN]", 'cyan) + " Object database query: " + $ansi:colorize(tool_args["reference"], 'white);
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
      "Truncate code for display";
      code_preview = tool_args["code"];
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
      "Explain messages are rendered as markdown - return raw content without ANSI formatting";
      return tool_args["message"];
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

  verb _check_user_eligible (this none this) owner: HACKER flags: "rxd"
    "Visor requires .programmer to use";
    {wearer} = args;
    wearer.programmer || raise(E_PERM, "The person wearing the visor is not a programmer, and not able to use its functions");
  endverb

  verb on_wear (this none this) owner: HACKER flags: "rxd"
    "Initialize and activate the HUD when worn";
    "Configure agent if not already done";
    if (!valid(this.agent))
      this:configure();
    endif
    "Reset context for fresh session";
    this.agent:reset_context();
    wearer = this.location;
    if (valid(wearer))
      "Narrative visual effect for wearing";
      wearer:inform_current($event:mk_info(wearer, "The visor's interface flickers to life as you adjust it over your eyes. A luminescent display materializes in the corner of your vision - cascading lines of data flow past in " + $ansi:colorize("electric blue", 'bright_blue) + " and " + $ansi:colorize("green", 'bright_green) + ". The world around you shimmers momentarily as the augmented reality overlay synchronizes with your neural patterns."));
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[BOOT]", 'bright_green) + " Neural link established. Augmented reality overlay: " + $ansi:colorize("ONLINE", 'green)):with_presentation_hint('inset));
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[READY]", 'green) + " Database inspection interface active. Commands: query <target>, reset"):with_presentation_hint('inset));
      "Show available token budget";
      this:_show_token_usage(wearer);
    endif
  endverb

  verb on_remove (this none this) owner: HACKER flags: "rxd"
    "Deactivate the HUD when removed";
    wearer = this.location;
    if (valid(wearer))
      "Show token usage before removal";
      this:_show_token_usage(wearer);
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[SHUTDOWN]", 'red) + " Neural link severed. Augmented reality overlay: " + $ansi:colorize("OFFLINE", 'bright_red)):with_presentation_hint('inset));
      "Narrative visual effect for removal";
      wearer:inform_current($event:mk_info(wearer, "The luminescent display flickers and dims, data streams dissolving into static. The augmented overlay fades from your peripheral vision like phosphor afterimages. As the neural link disconnects, you hear a faint electronic hiss - then silence. The world returns to its unaugmented state."));
    endif
  endverb

  verb reset (none none none) owner: HACKER flags: "rd"
    "Reset the visor context for a fresh session";
    if (!is_member(this, player.wearing))
      player:inform_current($event:mk_error(player, "You need to be wearing the visor to reset it."));
      return;
    endif
    if (!valid(this.agent))
      this:configure();
    endif
    this.agent:reset_context();
    player:inform_current($event:mk_info(player, $ansi:colorize("[RESET]", 'yellow) + " Neural buffer flushed. Session context cleared."):with_presentation_hint('inset));
  endverb

  verb query (this none none) owner: HACKER flags: "rd"
    "Query the data visor - prompts for input";
    if (!is_member(this, player.wearing))
      player:inform_current($event:mk_error(player, "You need to be wearing the visor to use it."));
      return;
    endif
    if (!valid(this.agent))
      this:configure();
    endif
    "Prompt for query text using metadata-based read";
    metadata = {{"input_type", "text"}, {"prompt", $ansi:colorize("[INTERFACE]", 'bright_blue) + " Enter your query:"}, {"placeholder", "Ask about objects, code, or database structure..."}};
    query = read(player, metadata):trim();
    if (!query)
      player:inform_current($event:mk_error(player, "Query cancelled - no input provided."));
      return;
    endif
    player:inform_current($event:mk_info(player, $ansi:colorize("[INTERFACE]", 'bright_blue) + " Query received: " + $ansi:colorize(query, 'white)):with_presentation_hint('inset));
    player:inform_current($event:mk_info(player, $ansi:colorize("[PROCESSING]", 'yellow) + " Analyzing request, accessing neural pathways..."):with_presentation_hint('inset));
    response = this:_send_with_continuation(query, "VISOR", 3);
    "DeepSeek returns markdown, so prefer djot rendering for nice formatting";
    event = $event:mk_info(player, response);
    event = event:with_metadata('preferred_content_types, {'text_djot, 'text_plain});
    event = event:with_presentation_hint('inset);
    player:inform_current(event);
  endverb
endobject