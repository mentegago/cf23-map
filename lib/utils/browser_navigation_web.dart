import 'package:web/web.dart' as web;

String browserCurrentUrl() => web.window.location.href;

void browserPushState(String path) =>
    web.window.history.pushState(null, '', path);

void browserAssign(String path) => web.window.location.assign(path);

void browserReload() => web.window.location.reload();
