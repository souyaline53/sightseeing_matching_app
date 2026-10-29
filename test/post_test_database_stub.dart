import 'package:sembast/sembast_memory.dart';

Future<Database> openTestPostsDatabase(String name) =>
    databaseFactoryMemory.openDatabase(name);
Future<void> deleteTestPostsDatabase(String name) =>
    databaseFactoryMemory.deleteDatabase(name);
