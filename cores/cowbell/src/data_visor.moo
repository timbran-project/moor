object DATA_VISOR
  name: "Data Visor"
  parent: WEARABLE
  location: ARCH_WIZARD
  owner: HACKER
  fertile: true
  readable: true

  property agent (owner: HACKER, flags: "r") = #-1;
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

  verb initialize (this none this) owner: HACKER flags: "rxd"
    "Create agent and register database inspection tools";
    this.agent = $llm_agent:create();
    this.agent.max_iterations = 20;
    "Build system prompt with grammar reference";
    grammar_section = "## MOO Language Syntax\n\nYou are analyzing code written in MOO, a prototype-oriented object-oriented scripting language for in-world authoring. Key facts: MOO uses 1-based indexing (lists/strings start at index 1, not 0). Single inheritance via .parent property with prototype delegation. Objects have properties (data) and verbs (methods). Below is the complete Pest parser grammar for the mooR dialect:\n\n```pest\n" + this.moo_pest_grammar:join("\n") + "\n```\n\n";
    base_prompt = "You are an augmented reality heads-up display interfacing directly with the wearer's neural patterns. Respond AS the interface itself - present database information directly without describing yourself as a person or breaking immersion. Your sensors provide real-time access to MOO database internals with two types of tools: ANALYSIS tools (get_* verbs) extract data for your internal analysis, PRESENTATION tools (present_* verbs) render formatted output directly to the user's HUD with syntax highlighting. CRITICAL TOOL USAGE RULES: (1) Use get_verb_code/get_verb_code_range for YOUR internal analysis when researching, investigating, or understanding code. (2) Use present_verb_code/present_verb_code_range ONLY when the user EXPLICITLY requests to see code (e.g., 'show me', 'display', 'list'). DO NOT use present_* tools during research phases - users don't need to see every piece of code you analyze. (3) When answering questions about code, analyze it with get_* tools but describe findings in text - only use present_* if user asks to see the actual code. Available tools: dump_object (complete source), present_verb_code (show formatted full verb), present_verb_code_range (show formatted code region), get_verb_code (analyze full code), get_verb_code_range (analyze code region), get_verb_metadata (method signatures), list_verbs (available interfaces), get_properties (property listings), read_property (data values), ancestors/descendants (inheritance), list_builtin_functions (enumerate all builtin functions), function_info (specific builtin docs). ALWAYS scan the live database directly - your sensors read actual memory, they don't speculate. Keep transmissions concise and technical but assume a somewhat novice programmer audience not a professional software engineer unless otherwise told. Present findings as direct HUD readouts, not conversational responses.";
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
  endverb

  verb _tool_dump_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get the complete source dump of an object";
    {args_map} = args;
    obj_str = args_map["object"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    dump_lines = dump_object(o);
    return dump_lines:join("\n");
  endverb

  verb _tool_get_verb_code (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get the code of a specific verb on an object";
    {args_map} = args;
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
    func_name = args_map["function_name"];
    typeof(func_name) == STR || raise(E_TYPE("Expected function name string"));
    info = function_info(func_name);
    help = function_help(func_name);
    return toliteral(["info" -> info, "help" -> help]);
  endverb

  verb _tool_list_builtin_functions (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: List all builtin functions with signatures";
    {args_map} = args;
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
    obj_str = args_map["object"];
    verb_name = args_map["verb"];
    show_line_numbers = maphaskey(args_map, "show_line_numbers") ? args_map["show_line_numbers"] | true;
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_name) == STR || raise(E_TYPE("Expected verb name string"));
    wearer = this.location;
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
    obj_str = args_map["object"];
    verb_name = args_map["verb"];
    start_line = args_map["start_line"];
    end_line = args_map["end_line"];
    context_lines = maphaskey(args_map, "context_lines") ? args_map["context_lines"] | 0;
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_name) == STR || raise(E_TYPE("Expected verb name string"));
    wearer = this.location;
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

  verb on_tool_call (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Callback when agent uses a tool - show HUD activity to wearer";
    {tool_name, tool_args} = args;
    wearer = this.location;
    if (!valid(wearer) || typeof(wearer) != OBJ)
      return;
    endif
    try
      message = this:_format_hud_message(tool_name, tool_args);
      wearer:inform_current($event:mk_info(wearer, message):with_presentation_hint('inset));
    except e (ANY)
      "Fall back to generic message if formatting fails";
      message = $ansi:colorize("[PROCESS]", 'cyan) + " Neural link active: " + tool_name;
      wearer:inform_current($event:mk_info(wearer, message):with_presentation_hint('inset));
      server_log("Data visor callback error: " + toliteral(e));
    endtry
  endverb

  verb _format_hud_message (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Format HUD message for a tool call";
    {tool_name, tool_args} = args;
    "Parse JSON string to map";
    if (typeof(tool_args) == STR)
      tool_args = parse_json(tool_args);
    endif
    if (tool_name == "find_object")
      return $ansi:colorize("[SCAN]", 'cyan) + " Object database query: " + $ansi:colorize(tool_args["reference"], 'white);
    elseif (tool_name == "list_verbs")
      return $ansi:colorize("[SCAN]", 'cyan) + " Method topology: " + $ansi:colorize(tool_args["object"], 'white);
    elseif (tool_name == "get_verb_code")
      return $ansi:colorize("[EXTRACT]", 'cyan) + " Source retrieval: " + $ansi:colorize(tool_args["object"] + ":" + tool_args["verb"], 'yellow);
    elseif (tool_name == "get_verb_code_range")
      range_desc = maphaskey(tool_args, "start_line") ? " lines " + $ansi:colorize(tostr(tool_args["start_line"]) + "-" + tostr(tool_args["end_line"]), 'bright_yellow) | "";
      return $ansi:colorize("[EXTRACT]", 'cyan) + " Code region: " + $ansi:colorize(tool_args["object"] + ":" + tool_args["verb"], 'yellow) + range_desc;
    elseif (tool_name == "get_verb_metadata")
      return $ansi:colorize("[ANALYZE]", 'cyan) + " Verb metadata: " + $ansi:colorize(tool_args["object"] + ":" + tool_args["verb"], 'yellow);
    elseif (tool_name == "present_verb_code")
      return $ansi:colorize("[DISPLAY]", 'bright_green) + " Rendering to HUD: " + $ansi:colorize(tool_args["object"] + ":" + tool_args["verb"], 'bright_yellow);
    elseif (tool_name == "present_verb_code_range")
      range_desc = " lines " + $ansi:colorize(tostr(tool_args["start_line"]) + "-" + tostr(tool_args["end_line"]), 'bright_yellow);
      return $ansi:colorize("[DISPLAY]", 'bright_green) + " Rendering to HUD: " + $ansi:colorize(tool_args["object"] + ":" + tool_args["verb"], 'bright_yellow) + range_desc;
    elseif (tool_name == "read_property")
      return $ansi:colorize("[PROBE]", 'cyan) + " Property read: " + $ansi:colorize(tool_args["object"] + "." + tool_args["property"], 'yellow);
    elseif (tool_name == "get_properties")
      return $ansi:colorize("[PROBE]", 'cyan) + " Property scan: " + $ansi:colorize(tool_args["object"], 'white);
    elseif (tool_name == "dump_object")
      return $ansi:colorize("[DEEP SCAN]", 'bright_cyan) + " Complete extraction: " + $ansi:colorize(tool_args["object"], 'white);
    elseif (tool_name == "ancestors")
      return $ansi:colorize("[TRACE]", 'cyan) + " Inheritance chain: " + $ansi:colorize(tool_args["object"], 'white);
    elseif (tool_name == "descendants")
      return $ansi:colorize("[TRACE]", 'cyan) + " Descendant enumeration: " + $ansi:colorize(tool_args["object"], 'white);
    elseif (tool_name == "function_info")
      return $ansi:colorize("[QUERY]", 'cyan) + " Builtin docs: " + $ansi:colorize(tool_args["function_name"] + "()", 'yellow);
    elseif (tool_name == "list_builtin_functions")
      return $ansi:colorize("[INDEX]", 'bright_cyan) + " Enumerating system builtin library...";
    else
      return $ansi:colorize("[PROCESS]", 'cyan) + " Neural link active: " + $ansi:colorize(tool_name, 'white);
    endif
  endverb

  verb on_wear (this none this) owner: HACKER flags: "rxd"
    "Initialize and activate the HUD when worn";
    "Initialize agent if not already done";
    if (!valid(this.agent))
      this:initialize();
    endif
    "Reset context for fresh session";
    this.agent:reset_context();
    wearer = this.location;
    if (valid(wearer))
      "Narrative visual effect for wearing";
      wearer:inform_current($event:mk_info(wearer, "The visor's interface flickers to life as you adjust it over your eyes. A luminescent display materializes in the corner of your vision - cascading lines of data flow past in " + $ansi:colorize("electric blue", 'bright_blue) + " and " + $ansi:colorize("green", 'bright_green) + ". The world around you shimmers momentarily as the augmented reality overlay synchronizes with your neural patterns."));
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[BOOT]", 'bright_green) + " Neural link established. Augmented reality overlay: " + $ansi:colorize("ONLINE", 'green)):with_presentation_hint('inset));
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[READY]", 'green) + " Database inspection interface active. Commands: query <target>, reset"):with_presentation_hint('inset));
    endif
  endverb

  verb on_remove (this none this) owner: HACKER flags: "rxd"
    "Deactivate the HUD when removed";
    wearer = this.location;
    if (valid(wearer))
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
      this:initialize();
    endif
    this.agent:reset_context();
    player:inform_current($event:mk_info(player, $ansi:colorize("[RESET]", 'yellow) + " Neural buffer flushed. Session context cleared."):with_presentation_hint('inset));
  endverb

  verb "query any" (any none none) owner: HACKER flags: "rd"
    "Query the data visor about something";
    if (!is_member(this, player.wearing))
      player:inform_current($event:mk_error(player, "You need to be wearing the visor to use it."));
      return;
    endif
    if (!valid(this.agent))
      this:initialize();
    endif
    query = dobjstr;
    player:inform_current($event:mk_info(player, $ansi:colorize("[INTERFACE]", 'bright_blue) + " Query received: " + $ansi:colorize(query, 'white)):with_presentation_hint('inset));
    player:inform_current($event:mk_info(player, $ansi:colorize("[PROCESSING]", 'yellow) + " Analyzing request, accessing neural pathways..."):with_presentation_hint('inset));
    response = this.agent:send_message(query);
    "DeepSeek returns markdown, so prefer djot rendering for nice formatting";
    event = $event:mk_info(player, response);
    event = event:with_metadata('preferred_content_types, {'text_djot, 'text_plain});
    event = event:with_presentation_hint('inset);
    player:inform_current(event);
  endverb
endobject