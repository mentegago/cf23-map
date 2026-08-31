import 'package:idb_shim/idb.dart';
import 'package:idb_shim/idb_browser.dart';

IdbFactory? catalogIdbFactory() => idbFactoryBrowser;
