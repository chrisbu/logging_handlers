library logviewer;

import 'package:polymer/polymer.dart';
import 'package:logging_handlers/logging_handlers_shared.dart';
import 'package:logging/logging.dart';

@CustomTag('log-viewer')
class LogViewer extends PolymerElement  {
 
  @observable
  List<String> messages = toObservable(new List<String>());
  
  LogViewer.created() : super.created();
  
  LogRecordTransformer transformer = new StringTransformer();
  
  void call(LogRecord logRecord) {
    messages.add(transformer.transform(logRecord));
  }
}