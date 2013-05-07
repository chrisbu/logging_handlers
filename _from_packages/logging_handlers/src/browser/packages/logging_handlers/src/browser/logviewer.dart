library logviewer;

import 'package:web_ui/web_ui.dart';
import 'package:logging_handlers/logging_handlers_shared.dart';

class LogViewer extends WebComponent  {
 
  @observable
  List<String> messages = new List<String>();
  
  LogRecordTransformer transformer;
  
  LogViewer() {
    transformer = new StringTransformer();
  }  
  
  void call(LogRecord logRecord) {
    messages.add(transformer.transform(logRecord));
  }
}