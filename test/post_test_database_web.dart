import 'package:sembast_web/sembast_web.dart';

Future<Database> openTestPostsDatabase(String name) =>
    databaseFactoryWeb.openDatabase(name);
Future<void> deleteTestPostsDatabase(String name) =>
    databaseFactoryWeb.deleteDatabase(name);
