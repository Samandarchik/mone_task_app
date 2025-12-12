import 'package:flutter/foundation.dart';

void pPrint(Object? object, [int level = 3, String? title]) {
  if (kDebugMode) {
    switch (level) {
      case 1:
        // green
        break;
      case 2:
        // yellow
        break;
      case 3:
        // red
        break;
      case 4:
        // blue
        break;
      case 5:
        // magenta
        break;
      case 6:
        // cyan
        break;
      default:
      // white
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
