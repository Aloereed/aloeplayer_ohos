import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/media_server_client.dart';
import 'package:aloeplayer/services/media_server_browser.dart';
import 'package:aloeplayer/services/media_server_query.dart';

const connection = MediaServerConnection(
    id: 'c',
    name: 'Test',
    url: 'https://example.invalid/prefix',
    userId: 'u',
    username: 'u',
    token: 't',
    kind: 'Jellyfin');

class Request {
  final String search;
  final String? parent;
  final int start;
  final CancelToken? cancel;
  final MediaServerQuery filters;
  final result = Completer<MediaServerPage>();
  Request(this.search, this.parent, this.start, this.cancel, this.filters);
}

class Client extends MediaServerClient {
  final requests = <Request>[];
  Client() : super(connection);
  @override
  Future<MediaServerPage> itemPage(
      {String? parent,
      String search = '',
      int start = 0,
      int limit = 100,
      MediaServerQuery query = const MediaServerQuery(),
      CancelToken? cancelToken}) {
    final request = Request(search, parent, start, cancelToken, query);
    requests.add(request);
    return request.result.future;
  }
}

MediaServerItem item(String id) =>
    MediaServerItem(id: id, name: id, type: 'Movie');
MediaServerPage page(List<String> ids,
        {int start = 0, int? total, int limit = 100}) =>
    MediaServerPage(
        items: ids.map(item).toList(),
        start: start,
        total: total,
        limit: limit);
void main() {
  test('album defaults to track order but explicit sorting survives navigation',
      () async {
    final client = Client();
    final browser = MediaServerBrowserController(client);
    addTearDown(browser.dispose);
    var pending = browser.enter(const MediaServerItem(
        id: 'album', name: 'Album', type: 'MusicAlbum', isFolder: true));
    expect(client.requests.last.filters.parameters['SortBy'],
        'ParentIndexNumber,IndexNumber,SortName');
    client.requests.last.result.complete(page([], total: 0));
    await pending;
    pending =
        browser.setFilters(const MediaServerQuery(sort: MediaServerSort.name));
    expect(client.requests.last.filters.parameters['SortBy'], 'SortName');
    client.requests.last.result.complete(page([], total: 0));
    await pending;
    pending = browser.setFilters(const MediaServerQuery());
    expect(client.requests.last.filters.sort, MediaServerSort.track);
    client.requests.last.result.complete(page([], total: 0));
    await pending;
    pending = browser.back();
    expect(client.requests.last.filters.sort, MediaServerSort.name);
    client.requests.last.result.complete(page([], total: 0));
    await pending;
  });
  test(
      'filter changes cancel stale pages; changed items leave filtered lists without skipping the next item',
      () async {
    final client = Client();
    final browser = MediaServerBrowserController(client);
    addTearDown(browser.dispose);
    final old = browser.load();
    final filtered = browser.setFilters(const MediaServerQuery(
        type: MediaServerTypeFilter.movies,
        watched: MediaServerWatchFilter.unwatched,
        sort: MediaServerSort.added,
        descending: true));
    expect(client.requests.first.cancel!.isCancelled, isTrue);
    expect(client.requests.last.filters.parameters['IsPlayed'], isFalse);
    client.requests.last.result.complete(page(['first'], total: 2));
    await filtered;
    client.requests.first.result.complete(page(['stale'], total: 1));
    await old;
    final more = browser.load(more: true);
    final pendingMore = client.requests.last;
    browser.updateItem(MediaServerItem.fromJson({
      'Id': 'first',
      'Type': 'Movie',
      'UserData': {'Played': true}
    }));
    expect(pendingMore.cancel!.isCancelled, isTrue);
    expect(client.requests.last.start, 0);
    client.requests.last.result.complete(page(['second'], total: 1));
    pendingMore.result.complete(page(['obsolete'], start: 1, total: 2));
    await more;
    await Future<void>.delayed(Duration.zero);
    expect(browser.items.single.id, 'second');
    expect(browser.total, 1);
    expect(browser.hasMore, isFalse);
  });
  test('new search cancels pending request and ignores a late response',
      () async {
    final client = Client();
    final browser = MediaServerBrowserController(client);
    addTearDown(browser.dispose);
    final old = browser.query('old');
    final latest = browser.query('latest');
    expect(client.requests.first.cancel!.isCancelled, isTrue);
    client.requests.last.result.complete(page(['new'], total: 1));
    await latest;
    client.requests.first.result.complete(page(['stale'], total: 1));
    await old;
    expect(browser.search, 'latest');
    expect(browser.items.single.id, 'new');
    expect(browser.busy, isFalse);
  });
  test(
      'server totals and raw page cursor survive duplicate entries and short pages',
      () async {
    final client = Client();
    final browser = MediaServerBrowserController(client);
    addTearDown(browser.dispose);
    var pending = browser.load();
    client.requests.last.result.complete(page(['a', 'b'], total: 5));
    await pending;
    expect(browser.hasMore, isTrue);
    pending = browser.load(more: true);
    expect(client.requests.last.start, 2);
    client.requests.last.result.complete(page(['b', 'c'], start: 2, total: 5));
    await pending;
    expect(browser.items.map((e) => e.id), ['a', 'b', 'c']);
    pending = browser.load(more: true);
    expect(client.requests.last.start, 4);
    client.requests.last.result.complete(page(['d'], start: 4, total: 5));
    await pending;
    expect(browser.hasMore, isFalse);
  });
  test('navigation clears query and stale error cannot replace current folder',
      () async {
    final client = Client();
    final browser = MediaServerBrowserController(client);
    addTearDown(browser.dispose);
    final search = browser.query('film');
    final folder = browser.enter(const MediaServerItem(
        id: 'folder', name: 'Folder', type: 'Folder', isFolder: true));
    expect(browser.search, '');
    expect(client.requests.last.parent, 'folder');
    client.requests.first.result.completeError(StateError('old failure'));
    await search;
    expect(browser.error, isNull);
    expect(browser.busy, isTrue);
    client.requests.last.result.complete(page([], total: 0));
    await folder;
    final back = browser.back();
    expect(client.requests.last.parent, isNull);
    client.requests.last.result.complete(page([], total: 0));
    await back;
  });
  test(
      'failed next page retains results and retries same cursor; disposal cancels read',
      () async {
    final client = Client();
    final browser = MediaServerBrowserController(client);
    var pending = browser.load();
    client.requests.last.result.complete(page(['a'], total: 3));
    await pending;
    pending = browser.load(more: true);
    client.requests.last.result.completeError(StateError('offline'));
    await pending;
    expect(browser.items.single.id, 'a');
    expect(browser.error, isNotNull);
    pending = browser.load(more: true);
    expect(client.requests.last.start, 1);
    browser.dispose();
    expect(client.requests.last.cancel!.isCancelled, isTrue);
    client.requests.last.result.complete(page(['b'], start: 1, total: 3));
    await pending;
  });
  test('empty pages end pagination even if server total is stale', () {
    expect(page([], start: 2, total: 20).hasMore, isFalse);
  });
  test('server ignoring StartIndex cannot repeat pages forever', () async {
    final client = Client();
    final browser = MediaServerBrowserController(client);
    addTearDown(browser.dispose);
    var pending = browser.load();
    client.requests.last.result.complete(page(['a', 'b'], limit: 2));
    await pending;
    pending = browser.load(more: true);
    client.requests.last.result.complete(page(['a', 'b'], start: 2, limit: 2));
    await pending;
    expect(browser.hasMore, isFalse);
    expect(browser.items.map((e) => e.id), ['a', 'b']);
  });
}
