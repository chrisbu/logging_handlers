logging_handlers
================

A package of logging handlers, for either the client or server, that uses the 
Dart SDK's [`logging` pub package](http://pub.dartlang.org/packages/logging)

Stop Using `print()` start using info()
--------------------

The logging_handlers package lets you use proper logging in your client-side or
server side Dart application.

Why?
----

Because when I use your library (or when you use my library), I want to control
the amount of logging output from your debug messages (and, I hope, you want to
do the same for my debug messages).  By using the Dart logging framework, we 
can both be happy.

The quickest (and dirtiest) way to replace `print()`
-------------------------------------

This is not the *best* way, but it's certainly better than `print()`.

0. Add `logging_handlers` package to pubspec.yaml
1. `import 'package:logging_handlers/logging_handlers_shared.dnart';`
2. Use `debug(msg)`, `info(msg)`, `warn(msg)`, `error(msg)` as appropriate.
3. Somewhere in your initialization code (start of your unit tests, `main()` 
or other initialization code), call `startQuickLogging()`

Note: Dart's logging has more fine grained logging levels - the top-level 
functions above are shorthand for some of these:

                 FINEST // highly detailed tracing
                 FINER // fairly detailed tracing 
    debug(msg) = FINE // tracing information
                 CONFIG // static configuration messages
    info(msg)  = INFO // informational messages
    warn(msg)  = WARNING // potential problems
    error(msg) = SEVERE // serious failures
                 SHOUT // extra debugging loudness

But see below for better ways, that allow users of your code more control, and 
let you have finer-grained control over logging.

The better way
--------------

Give your logger a name, such as your libraries name when you call one of the 
logging functions, for example: `debug("Hello World", "my_library_name");`

The best way
------------

Create a top-level `logger` instance in your library, and give it the name of 
your library

    library my_library;
    import 'package:logging_handlers/logging_handlers_shared.dnart';

    final _logger = new Logger("my_library");

    constructor
    	_logger.fine("Hello World");
    	_logger.error("Something bad has happened");
    }