import 'dart:ffi';

import 'package:libass_binding/libass_binding.dart';

void main() {
  final dylib = DynamicLibrary.process();
  final libass = LibassBindings(dylib);
  print('awesome: ${libass.ass_library_version()}');
}
