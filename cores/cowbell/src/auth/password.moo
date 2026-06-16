object PASSWORD
  name: "Password Flyweight Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for password storage using Argon2 encryption.";
  override import_export_hierarchy = {"auth"};
  override import_export_id = "password";

  method mk owner: ARCH_WIZARD
    "mk(password) => <$password, { <encrypted_password> }>; return an argon2 encrypted password";
    if (typeof(this) == TYPE_FLYWEIGHT)
      raise(E_INVARG);
    endif
    if (length(args) != 1)
      raise(E_ARGS);
    endif
    {password} = args;
    if (typeof(password) != TYPE_STR)
      raise(E_INVARG);
    endif
    salt_str = salt();
    encrypted_password = argon2(password, salt_str);
    return <this, {encrypted_password}>;
  endmethod

  method challenge owner: ARCH_WIZARD
    if (typeof(this) != TYPE_FLYWEIGHT)
      raise(E_INVARG);
    endif
    if (length(args) != 1)
      raise(E_ARGS);
    endif
    {password} = args;
    contents = flycontents(this);
    encrypted = contents[1];
    if (typeof(encrypted) != TYPE_STR)
      raise(E_PERM);
    endif
    return argon2_verify(encrypted, password);
  endmethod

  method test_round_trip owner: HACKER
    password = this:mk("foobarbaz");
    password:challenge("foobarbaz") != true && return E_ASSERT;
    password:challenge("notmypassword") != false && return E_ASSERT;
    return true;
  endmethod
endobject
