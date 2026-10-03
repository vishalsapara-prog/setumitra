/// Shared test bootstrap: makes the real, protected `DatabaseService` /
/// `AutoFillMappingService` (sqflite-backed) actually work under plain
/// `flutter test`, which has no platform channel for the sqflite plugin.
/// `sqflite_common_ffi` provides a pure-Dart/FFI SQLite implementation
/// instead -- a standard, widely-used pattern for testing sqflite code,
/// not a stand-in/fake: these tests exercise the real DatabaseService
/// class and real SQL.
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _initialized = false;

void initSqfliteFfiForTests() {
  if (_initialized) return;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  _initialized = true;
}
