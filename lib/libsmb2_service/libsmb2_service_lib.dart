// libsmb2_service - Flutter FFI wrapper for libsmb2.so
//
// This library provides a Flutter interface to libsmb2 using FFI.
// It implements the same interface as smb_service.dart but uses
// the native libsmb2 library instead of the smb_connect package.

library libsmb2_service;

export 'libsmb2_bindings.dart';
export 'libsmb2_service.dart';
export 'libsmb2_file.dart';
export 'smb_file.dart';
export 'smb_file_adapter.dart';
