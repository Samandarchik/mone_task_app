import 'package:flutter/foundation.dart';

void pPrint(Object? object, [int level = 3, String? title]) {
  if (kDebugMode) {
    String color;
    switch (level) {
      case 1:
        color = '\x1B[32m'; // green
        break;
      case 2:
        color = '\x1B[33m'; // yellow
        break;
      case 3:
        color = '\x1B[31m'; // red
        break;
      case 4:
        color = '\x1B[34m'; // blue
        break;
      case 5:
        color = '\x1B[35m'; // magenta
        break;
      case 6:
        color = '\x1B[36m'; // cyan
        break;
      default:
        color = '\x1B[37m'; // white
    }

    title ??= 'Debug';
    //     print(
    //       '''$color
    // ************$title*********
    // ${object.toString()}
    // ************$title*********\x1B[0m''',

    //     );
  }
}
