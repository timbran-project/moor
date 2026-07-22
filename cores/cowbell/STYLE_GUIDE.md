## mooR dialect programming style guide for cowbell

### general philosophy

- readable
- minimal but not terse
- don't repeat yourself
- respect the language and its idioms

### caveats in general about MOO

- 1-indexed lists and strings
- map and list syntax is "backwards" from e.g. Python:
  - `{ 1, 2, 3 }` is a list
  - `[ 1 -> 2, 3 -> 4]` is a map
- string comparisons are case insensitive by default.  use `strcmp` for case sensitive compares
- MOO has a nice fancy destructuring assignment operator. use it.
  - `{ a, b, c } = { 1, 2, 3}; return {c, b, a};` returns `{3, 2, 1,}`
  - `{ a, ?b = 3, @c } = {1, 2, 3, 4}; return {c, b, a,}` returns `{{3, 4}, 2, 1}`
- many bugs come from expecting MOO to behave like Python or JavaScript. It isn't. It is its own language, don't fight it.


### some mooR niceties
- mooR adds lexical scoping - begin/end blocks, and `let` and `const` for local scoped variable assignment
- we also add for comprehensions

### general code structuring

- always prefer early returns instead of chains of if/elseif/else/endif
  - reduces nesting
  - makes it clear the order of flow
- as part and in addition to early returns, always deal with the negative / error cases first
  - encourages finding and dealing with errors & validation conditions up front
  - makes it clearer to the reader what the contract of the method is
- use guard conditions where possible, instead of `if` blocks:

  instead of:
  ```moocode
	  if (user:is_bad_user())
		raise(E_BADUSER);
	  endif
  ```
  
  do:
  ```moocode
	  user:is_bad_user() && raise(E_BADUSER);
  ```
  
  or:
  ```moocode
	  !user:is_bad_user() || raise(E_BADUSER);
  ```

### inline documentation
- always start methods with a brief docstring describing the function
- docstrings use string literals on a line by themselves

### verbs
- in MOO, *method verbs* *always* have argspec "this none this" and flags `rxd` no exception
- but *command verbs* have meaningful arg/prepspecs and usually do not have `x` flags
- private "methods" should be prefixed with _, though this rule hasn't been consistently applied 
  - e.g. `_is_gagged_user()`
- unit tests with `test_`
  - unit tests should be standalone and not require any scaffolding or setup, and should clean up after themselves
  - if a unit test creates objects it should either use anonymous objects or explicitly recycle

### errors and exceptions
- we put 'd' flag on verbs to cause errors to propagate as exceptions.  only "legacy" MOO code has this turned off
- in "method" verbs we should use and propagate exceptions, but in "command" verbs we catch and turn them into meaningful output
- catching and silenlty eating exceptions a bad practice and makes it hard to diagnose when things go wrong.
  - MOO has a weak type system, and often has runtime type errors, hiding them is bad practice
- MOO has two ways of catching exceptions:
  ```
  try
    <stuff>
  except e (ANY)   [or some specific exception]
    <....>
  endtry
  ```
  
  and
  
  ```
  `<stuff> ! ANY => <otherstuff>';
  ```
  
  Note that we use both kinds of ticks, forward and back. this can confuse some tools.


### perms
- MOO's permission model is a bit dangerous, with some footguns. it's *easy* to accidentally give more permissions than you should, or give the wrong perms.
- because in MOO a verb always runs with the permissions of the *owner of the verb*
- this means that if a verb is owned by a wizard character it will have super powers
- `set_task_perms()` is used to change the execution of the verb to act with a different set of perms
  - `set_task_perms()` *cannot* escalate permissions. That is, if the task perms have been downgraded to user, it's logically not possible to "go back up". Likewise, if the verb is running as a user, it cannot set perms to another user or a wizard.
- wizard-owned verbs are often necessary to execute various system functions but we should be very careful with them
- verbs with powerful permissions should always start with some guard to check on the caller / caller_perms
- for example, if a verb is "private", it could start with the following guard to stop others from using it
  ```moocode
	  caller == this || raise(E_PERM);
  ```

- likewise we can have guards like:
  ```moocode
	  valid(caller_perms()) && caller_perms().wizard || raise(E_PERM);
  ```


