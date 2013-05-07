logging_handlers
================

A package of logging handlers, for either the client or server, that uses the 
Dart SDK's [`logging` pub package](http://pub.dartlang.org/packages/logging)

For a quick refrence on how to use this package, [go here](https://github.com/chrisbu/logging_handlers#quick-reference)

Stop Using `print(msg)` start using `info(msg)`
--------------------

When you use `print()`, other users of your code have to see all your internal
debug logging (I know I'm guilty of this, too).  

The `logging_handlers` package lets you use proper logging in your 
client-side or server side Dart application.

Why?
----

When I use your library (or when you use my library), I want to control
the amount of logging output from your debug messages (and, I hope, you want to
do the same for my debug messages).  By using the Dart logging framework, we 
can both be happy.

There are two parts involved in logging:
-------------------------------

1. Sending log messages into a logging framework
2. Outputting the log messages somewhere (eg, to the stdout, a file, the browser).

Dart's `print()` sort of covers both of these use cases, 
and the quick'n'dirty alternative described
below also does the same thing.  It's not the best way, but at least it means 
that log messages can be output somewhere other than the console 
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
`JSON`able `Map`,  and you can output a log message to the console similar to 
`print()`, to a server-side file, or to a client-side web-ui component (or a 
mixture).  

The quickest (and dirtiest) way to replace `print()`
-------------------------------------

This is not the *best* way, but it's certainly better than `print()`.

0. Add `logging_handlers` package to pubspec.yaml
1. `import 'package:logging_handlers/logging_handlers_shared.dart';`
2. Use `debug(msg)`, `info(msg)`, `warn(msg)`, `error(msg)` as appropriate.
3. Somewhere in your initialization code (start of your unit tests, `main()` 
or other initialization code), call `startQuickLogging()`

For example:

    import 'package:logging_handlers/logging_handlers_shared.dart';

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
    import 'package:logging_handlers/logging_handlers_shared.dart';

    class Foo() {
      Foo() {
      	debug("Foo is created", "my_library"); // calls debug with your library name
      }
    }

    main() {
      startQuickLogging();
      new Foo(); 
    }

this outputs:

    2013-05-06 16:42:42.593		[INFO]:	Quick'n'Dirty logging is enabled.  It's better to do it properly, though.
    2013-05-06 16:42:42.604 my_library		[FINE]:	Foo is created

When you include your library name in your log messages, other users of your 
code can filter your log messages out (more on that later).


The best way to implement logging in your libraries
------------

Create a `Logger` instance in your library, and give it the name of 
your library:

    library my_library;
    import 'package:logging_handlers/logging_handlers_shared.dart';

    final _logger = new Logger("my_library");

    class MyClass {
    	MyClass() {
	       _logger.fine("MyClass created");
	    }

	    foo() {
	      _logger.error("Something bad has happened");
	    }
    }


You can have as many loggers as you need, and they can be hierarchical (using 
a `.` to separate).  For example, you might have a top-level logger, 
and individual loggers for specific classes:

    library my_library;
    import 'package:logging_handlers/logging_handlers_shared.dart';

    final _libraryLogger = new Logger("my_library"); // top level logger

    class MyClass {

      // MyClass logger is a child of my_library logger
      static final _logger = new Logger("my_library.MyClass");

      MyClass() {
         MyClass._logger.fine("MyClass created"); // using class logger
      }

      foo() {
        _libraryLogger.error("Something bad has happened"); // using top-level logger
      }
    }


When you use hierarchical logging, you (and your code's users) can start to 
take control over what actually gets output, and to where (such as outputting 
ALL logging for MyClass, but only WARNING, SEVERE and SHOUT logging for the
library).

**Now that you've seen how to emit log messages into a framework, let's take
a look at how to control where those messages go**

Controlling log message output
---------------------------------

The code in your classes and libraries don't actually run until you pull them
into a Dart application (or unit test) via the top-level `main()` function.

In the `main()` function, you need to initialize the logging framework with
a logging handler.  The simplest version of this is the `PrintHandler`, which
outputs log messages to the console in the same way that `print()` does.

Let's assume that you've implemented logging using "the best way" which
contains your logger name.

    // the SDK logging framework
    import 'package:logging/logging.dart'; 
    // Handlers that are shared between client and server
    import 'package:logging_handlers/logging_handlers_shared.dart'; 
    // your library, from above...
    import 'my_library'; 

    main() {
      Logger.root.onRecord.listen(new PrintHandler()); // default PrintHandler
      var myclass = new MyClass(); // from above - outputs log message
    }

If you're on the server-side, and you want to log to a file, the 
`logging_handlers` package includes a very simple (synchronous) filesystem 
log file handler: `SyncFileLoggingHandler`.

    // the SDK logging framework
    import 'package:logging/logging.dart'; 
    // Handlers that run server-side
    import 'package:logging_handlers/server_logging_handlers.dart'; 
    // your library, from above...
    import 'my_library'; 

    main() {
      Logger.root.onRecord.listen(new SyncFileLoggingHandler("myLogFile.txt")); 
      var myclass = new MyClass(); // from above - outputs log message
    }  

And if you're on the client side, there's a handy (and incredibly basic)
web component `<x-loggerui>` to output log messages on screen.

In your Web UI enabled application, your HTML will look something like this:

    <html>
      <head>
        <!-- import the loggerui component -->
        <link rel="import" href="package:logging_handlers/src/client/loggerui.html">
      </head>
 
      <body>   
        <!-- other content... -->

        <x-loggerui></x-loggerui>  <!-- Logger widget -->

        <!-- standard app scripts -->
        <script type="application/dart" src="test.dart"></script>
        <script src="packages/browser/dart.js"></script>
      </body>
    </html>

And in your app's main() function, you call `attachXLoggerUi()` like this:

    import 'package:logging_handlers/browser_logging_handlers.dart';

    main() {
      attachXLoggerUi(); // lives in the browser_logging_handlers library
    }

The `attachXLoggerUi` function runs in the next event loop iteration after main 
(using `Timer.run`), so any startup logging won't appear.  This is because the
web component's themselves aren't available until the next event loop.

**Attaching multiple handlers**

Sometimes, you want to attach multiple handlers.  That's fine, because the 
logging framework uses Streams, so you just need to use `asBroadcastStream()`:

    main() {
      var loggerStream = Logger.root.onRecord.asBroadcastStream();
      // attach the PrintHandler and the File logging handler
      loggerStream.listen(new PrintHandler()); 
      loggerStream.listen(new SyncFileLoggingHandler("myLogFile.txt"));       
    }  


**Note** _At present, the implementations of the client and server handlers
are fairly basic, but given time (and your help?), they should get greater
functionality.  Ideas include: Allowing the x-loggerui to filter based on level.  
or creating an async version of the server side logger._

Getting more control over the output
------------------------------------

Now you have seen what can be output, let's take a look at how you customize that.

Each of the handlers (`LoggerUi`, `SyncFileLoggingHandler` and `PrintHandler`)
implement a `BaseLoggingHandler` interface.  These have a `LogRecordTransformer`
instance, that transforms an SDK `LogRecord` into some other format.  

The `logging_handlers` package contains two transformers that implement
`LogRecordTransformer`: `StringTransformer`
and `MapTransformer`.  All three handlers use a default implementation of a 
`StringTransformer`, but you can pass an alternative transformer into the 
constructor of both the `PrintHandler` or `SyncFileLoggingHandler`.  

**StringTransformer**

The `StringTransformer` lets you control the fields that get output, for example:

    main() {
      var fileHandler = 
          new SyncFileLoggingHandler("logfile.txt", transformer: new StringTransformer("%m"));
      Logger.root.onRecord.listen(fileHandler); // default 
      var myclass = new MyClass(); // from above - outputs log message
    }

The `StringTransformer` allows formatting strings to specify the output.  %m is 
just the message without all the other information, and replicates the print 
command.  

The full list of formatting strings is shown below:

    %p = Outputs LogRecord.level
    %m = Outputs LogRecord.message
    %n = Outputs the Logger.name
    %t = Outputs the timestamp according to the Date Time Format specified
    %s = Outputs the logger sequence 
    %x = Outputs the exception
    %e = Outputs the exception message

The default formatting strings are shown below (with `\t` for tab separation):

    DEFAULT_MESSAGE_FORMAT = "%t\t%n\t[%p]:\t%m";
    DEFAULT_EXCEPTION_FORMAT = "\n%e\n%x";
    DEFAULT_DATE_TIME_FORMAT = "yyyy.mm.dd HH:mm:ss.SSS Z";    

You can customize all of these when you create a logger handler.


Replacing the `print()` command
---------------------------

Now that you have seen some of the formatting available, let's see how you can
actually replace the `print()` command:


    main() {
      // simulate existing print command by only outputting the message
      Logger.root.onRecord.listen(new PrintHandler(messageFormat:"%m")); 
    }

Taking control: Logging levels and heirarchical loggers
--------------------------------------------------------

Let's suppose that you are using my library.

We have `your_library` and `my_library`

You don't want to see my logging when you test your library.  
How can you control it?

Let's look at some code that outputs logging from `your_library` but not 
`my_library`:

    import 'package:my_library/my_library.dart'; // don't want to see logging here
    import 'your_library.dart';  // Show logging from this library please :)

    import 'package:logging/logging.dart'; 
    import 'package:logging_handlers/logging_handlers_shared.dart'; 

    main() {
      hierarchicalLoggingEnabled = true; // set this to true - its part of Logging SDK

      // now control the logging.
      // Turn off all logging first
      Logger.root.level = Level.OFF;
      Logger.root.onRecord.listen(new PrintHandler());
 
      // create a logger for your library 
      // (there will be a single instance for each logger with the same name)
      // and set the level to ALL
      new Logger("your_library")..level = Level.ALL;
      
      doSomethingInYourLibrary(); // logging is output to console
      doSomethingInMyLibrary(); // logging is not be output      
    }

Now let's use the hierarchy to use different logging for a specific class 
(assuming that you have a class logger created for `your_library.YourClass`):


    main() {
      hierarchicalLoggingEnabled = true; // set this to true - its part of Logging SDK

      // now control the logging.
      // Turn off all logging first
      Logger.root.level = Level.OFF;
      Logger.root.onRecord.listen(new PrintHandler());
 
      // create a logger for your library 
      // (there is only a single instance for each logger with the same name)
      // and set the level to ALL
      new Logger("your_library")..level = Level.INFO;
      new Logger("your_library.YourClass")..level = Level.ALL; 

      
      doSomethingInYourLibrary(); // Only INFO logging is output to console
      new YourClass(); // All logging output to the console
      doSomethingInMyLibrary(); // logging is not be output      
    }

Quick Reference
-------

**Logging best practice**

1. Add `logging` and `logging_handlers` to pubspec
2. Import the `logging` SDK where you want to write log messages

    ```
    import 'package:logging/logging.dart'; 
    ```

3. Create a logger (or loggers), and use them

    ```
    final _libraryLogger = new Logger("my_library");

    doSomething() {
      _libraryLogger.info("Something is done")
    }

    class MyClass {
      final _classLogger = new Logger("my_library.MyClass")

      MyClass() {
        _classLogger.fine("MyClass is constructed");
      }
    }
    ```

4. When you use your library / class, and want to output some logging, create
an instance of a `LoggingHandler` and attach it to the root logger

    ```
    import 'package:logging_handlers/logging_handlers_shared.dart'; 
    import 'your_library';

    main() {
      Logger.root.onRecord.listen(new PrintHandler());
    }
    ```

5. When you want finer control over what get's output, use hierarchical loggin
and set levels
  
    ```
    import 'package:logging_handlers/logging_handlers_shared.dart'; 
    import 'your_library';
    import 'package:my_library/my_library.dart';

    main() {
      Logger.root.onRecord.listen(new PrintHandler());
      Logger.root.level = Level.OFF; // log nothing by default
      new Logger("your_library")..level = Level.ALL; // log all in your library    
    }
    ```

*Server handlers are found here:*

    import 'package:logging_handlers/server_logging_handlers.dart'; 

*Client logging handlers are found here:*

    import 'package:logging_handlers/browser_logging_handlers.dart'; 

*Web UI component is here:*

    <link rel="import" href="package:logging_handlers/src/client/loggerui.html">
    ...
    <x-loggerui></x-loggerui>

    ... 
    // and in your script, call:
    import 'package:logging/logging.dart'; 
    import 'package:logging_handlers/browser_logging_handlers.dart'; 

    main() {
      hierarchicalLoggingEnabled = true;
      attachXLoggerUi();
    }


Caveats
--------

The Logger framework (as at M4), has a TODO about logging exceptions.  At the 
moment _it doesn't_.  If you want to log exceptions, add the exception text to
the log message.

If you find any problems or errors, then please let me know.
This was current as at r21823