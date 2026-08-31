export 'catalog_idb_factory_stub.dart'
    if (dart.library.html) 'catalog_idb_factory_web.dart'
    if (dart.library.js_interop) 'catalog_idb_factory_web.dart';
