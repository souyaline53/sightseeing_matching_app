import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openPostsDatabase() async {
  final directory = await getApplicationSupportDirectory();
  final path = directory.uri.resolve('tabisaki_posts_v1.db').toFilePath();
  return databaseFactoryIo.openDatabase(path);
}
