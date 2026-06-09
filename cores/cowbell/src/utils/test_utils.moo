object TEST_UTILS
  name: "Test Utilities"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: HACKER
  readable: true

  override description = "Shared helpers for cowbell unit tests.";
  override import_export_hierarchy = {"utils"};
  override import_export_id = "test_utils";

  verb assert_true (this none this) owner: HACKER flags: "rxd"
    "Assert that condition is true.";
    {condition, ?message = "Expected true"} = args;
    condition || raise(E_ASSERT, message);
    return true;
  endverb

  verb assert_false (this none this) owner: HACKER flags: "rxd"
    "Assert that condition is false.";
    {condition, ?message = "Expected false"} = args;
    !condition || raise(E_ASSERT, message);
    return true;
  endverb

  verb assert_eq (this none this) owner: HACKER flags: "rxd"
    "Assert that actual equals expected.";
    {actual, expected, ?message = "Values differ"} = args;
    actual == expected || raise(E_ASSERT, message + ": expected " + toliteral(expected) + ", got " + toliteral(actual));
    return true;
  endverb

  verb assert_type (this none this) owner: HACKER flags: "rxd"
    "Assert that value has the expected MOO type constant.";
    {value, expected_type, ?message = "Type mismatch"} = args;
    typeof(value) == expected_type || raise(E_ASSERT, message + ": expected type " + tostr(expected_type) + ", got " + tostr(typeof(value)));
    return true;
  endverb

  verb assert_raises (this none this) owner: HACKER flags: "rxd"
    "Assert that obj:verb(@call_args) raises expected_error.";
    {expected_error, obj, verb_name, ?call_args = {}, ?message = "Expected error"} = args;
    try
      obj:(verb_name)(@call_args);
    except e (ANY)
      e[1] == expected_error || raise(E_ASSERT, message + ": expected " + tostr(expected_error) + ", got " + tostr(e[1]));
      return true;
    endtry
    raise(E_ASSERT, message + ": no error raised");
  endverb

  verb anonymous (this none this) owner: HACKER flags: "rxd"
    "Create an anonymous child of proto for test fixtures.";
    {proto} = args;
    return proto:create(true);
  endverb

  verb destroy_if_valid (this none this) owner: HACKER flags: "rxd"
    "Destroy a persistent fixture if it is valid. Anonymous objects cannot be destroyed.";
    {obj} = args;
    if (valid(obj) && !is_anonymous(obj))
      obj:destroy();
    endif
    return true;
  endverb

  verb test_assertions (this none this) owner: HACKER flags: "rxd"
    "Exercise the basic assertion helpers.";
    this:assert_true(true, "true should pass");
    this:assert_false(false, "false should pass");
    this:assert_eq("cow", "cow", "equal strings should pass");
    this:assert_type("cow", TYPE_STR, "string should have TYPE_STR");
    this:assert_raises(E_ASSERT, this, "assert_eq", {"cow", "bell", "mismatch should raise"}, "assert_eq mismatch");
    this:assert_eq($arch_wizard:pronouns_display(), "they/them", "player pronouns display should be readable");
    this:assert_eq($henri:pronouns_display(), "he/him", "actor pronouns display should be readable");
    return true;
  endverb

  verb test_anonymous_fixture_helpers (this none this) owner: HACKER flags: "rxd"
    "Exercise anonymous creation and safe cleanup helpers.";
    anon = this:anonymous($root);
    this:assert_true(is_anonymous(anon), "anonymous helper should create anonymous objects");
    this:destroy_if_valid(anon);
    this:assert_true(valid(anon), "destroy_if_valid should leave anonymous objects alone");
    scratch = create($root);
    try
      this:assert_false(is_anonymous(scratch), "default create should make a persistent object");
      this:destroy_if_valid(scratch);
      this:assert_false(valid(scratch), "destroy_if_valid should destroy persistent objects");
    finally
      valid(scratch) && recycle(scratch);
    endtry
    return true;
  endverb
endobject
