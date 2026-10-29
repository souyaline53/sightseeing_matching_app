import 'package:sembast_web/sembast_web.dart';

Future<Database> openPostsDatabase() =>
    databaseFactoryWeb.openDatabase('tabisaki.posts.v1');
