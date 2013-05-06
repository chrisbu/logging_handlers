logging_handlers
================

A package of logging handlers, for either the client or server, that uses the 
Dart SDK's [`logging` pub package](http://pub.dartlang.org/packages/logging)

Stop Using `print()` start using `info()`
--------------------

The logging_handlers package lets you use proper logging in your client-side or
server side Dart application.

Why?
----

Because when I use your library (or when you use my library), I want to control
the amount of logging output from your debug messages (and, I hope, you want to
do the same for my debug messages).  By using the Dart logging framework, we 
can both be happy.

There are two parts to logging:
-------------------------------

1. Sending log messages into a logging framework
2. Outputting the log messages (eg, to the stdout, a file, the browser).

Dart's `print()` sort of covers both of these use cases, 
and the quick'n'dirty alternative described
below also does the same thing.  It's not the best way, but at least it means 
that log messages can be putput somewhere other than the console 
(such as a file).

First, some background about logging
-------------------

Dart's `logging` pub package, that forms part of the Dart SDK, covers use-case
1, in other words, it lets you send log messages into a logging framework.  
This framework lets you attach **handlers** to that framework that can listen
to the stream of log messages.

This package, `logging_handlers` provides some default handlers that 
lets you output messages to a variety of locations, in a variety of formats.

At the moment, you can output a log message as a tab delimited `String` or a 
`JSON`able `Map`,  and you can output a log message to the console 

The quickest (and dirtiest) way to replace `print()`
-------------------------------------

This is not the *best* way, but it's certainly better than `print()`.

0. Add `logging_handlers` package to pubspec.yaml
1. `import 'package:logging_handlers/logging_handlers_shared.dart';`
2. Use `debug(msg)`, `info(msg)`, `warn(msg)`, `error(msg)` as appropriate.
3. Somewhere in your initialization code (start of your unit tests, `main()` 
or other initialization code), call `startQuickLogging()`

For example:

    import 'package:logging_handlers/logging_handlers_shared.dnart';

    main() {
    	startQuickLogging();
    	info("Hello World");
    }

will output to the console:

    2013-05-06 16:42:42.593		[INFO]:	Quick'n'Dirty logging is enabled.  It's better to do it properly, though.
    2013-05-06 16:42:42.604		[INFO]:	Hello World

**Note:** Dart's logging has more fine grained logging levels - the top-level 
functions above are shorthand for some of these:

                 FINEST // highly detailed tracing
                 FINER // fairly detailed tracing 
    debug(msg) = FINE // tracing information
                 CONFIG // static configuration messages
    info(msg)  = INFO // informational messages
    warn(msg)  = WARNING // potential problems
    error(msg) = SEVERE // serious failures
                 SHOUT // extra debugging loudness

But see below for better ways that allow users of your code more control over
what actually gets output, and let you have finer-grained control over logging.

The a slightly better way (but still a bit quick'n'dirty) to replace `print()`
--------------

Let users of your code filter out your specific log messages by giving your
log messages a name.  The best name is the name of your library.
for example: 

    library my_library;
    import 'package:logging_handlers/logging_handlers_shared.dnart';

    class Foo() {
      Foo() {
      	debug("Foo is created", "my_library");
      }
    }

    main() {
      startQuickLogging();
      new Foo(); 
    }

this outputs:

    2013-05-06 16:42:42.593		[INFO]:	Quick'n'Dirty logging is enabled.  It's better to do it properly, though.
    2013-05-06 16:42:42.604 my_library		[INFO]:	Foo is created



The best way to implement logging
------------

Create a top-level `logger` instance in your library, and give it the name of 
your library:

    library my_library;
    import 'package:logging_handlers/logging_handlers_shared.dnart';

    final _logger = new Logger("my_library");

    class MyClass {
    	MyClass() {
	       _logger.fine("MyClass created");
	    }

	    foo() {
	      _logger.error("Something bad has happened");
	    }
    }


Then, users of your library (including yourself), can output the logging entries
to a variety of different handlers

// cont...