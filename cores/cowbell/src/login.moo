object LOGIN
    name: "Login Service"
    parent: ROOT
    owner: ARCH_WIZARD
    readable: true

    property welcome_message (owner: ARCH_WIZARD, flags: "rc") = {"## Welcome to the _mooR_ *Cowbell* core.", "", "connect with `archwizard` `test` to log in.", "", "You will probably want to change this text which is stored in $login.welcome_message property."};
endobject
