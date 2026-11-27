import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_food_tracker_app/main.dart';
import 'package:flutter_food_tracker_app/models/food_photo.dart';
import 'package:flutter_food_tracker_app/models/food_tracker.dart';
import 'package:flutter_food_tracker_app/services/food_service.dart';
import 'package:flutter_food_tracker_app/services/supabase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/synthetic_image.dart';

const _enabled = bool.fromEnvironment('FOOD_TRACKER_LIVE_TEST');
const _url = String.fromEnvironment('SUPABASE_URL');
const _key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

FoodInput _input(
  String name, {
  String meal = 'กลางวัน',
  String date = '2026-11-27',
  double price = 0,
}) => FoodInput(name: name, meal: meal, date: date, price: price, person: 2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'live anon CRUD, storage lifecycle, constraints, and grants',
    () async {
      final run = _LiveRun();
      addTearDown(run.close);
      try {
        final initial = await run.read();
        expect(initial, isEmpty);
        expect(run.client.auth.currentSession, isNull);

        await expectLater(
          run.service.addFood(_input('${run.tag}-validation', price: -1), null),
          throwsFormatException,
        );
        expect(run.trace.dbWrites, 0);

        final blue = await FoodPhoto.decode(await syntheticPng(0xff326cd8));
        final green = await FoodPhoto.decode(await syntheticPng(0xff3ba366));
        final empty = (await run.service.addFood(
          _input('${run.tag}-no-photo', meal: 'ว่าง', date: '2026-11-26'),
          null,
        )).food;
        run.record(empty);
        expect(empty.imageUrl, isNull);
        final original = (await run.service.addFood(
          _input('${run.tag}-photo'),
          blue,
        )).food;
        run.record(original);
        final oldPath = run.service.objectPath(original.imageUrl)!;
        expect((await run.read()).map((row) => row.id), [
          original.id,
          empty.id,
        ]);
        final publicImage = await run.trace.get(Uri.parse(original.imageUrl!));
        expect(publicImage.statusCode, 200);
        expect(publicImage.bodyBytes, orderedEquals(blue.bytes));
        final same = await run.addImageReference(
          'same-url',
          original.imageUrl!,
        );
        final alias = await run.addImageReference(
          'query-url',
          '${original.imageUrl!}?download=sample.png',
        );

        final changed = await run.service.updateFood(
          original,
          _input('${run.tag}-edit', meal: 'เย็น', price: 125.5),
          null,
        );
        expect(changed.food.id, original.id);
        expect(changed.food.imageUrl == original.imageUrl, isTrue);
        expect(changed.food.input.price, 125.5);
        await expectLater(
          run.service.updateFood(original, _input('${run.tag}-stale'), green),
          throwsA(
            isA<FoodActionException>().having(
              (e) => e.refresh,
              'refresh',
              true,
            ),
          ),
        );
        expect(await run.exists(run.trace.uploads.last), isFalse);

        final replaced = await run.service.updateFood(
          changed.food,
          _input('${run.tag}-replaced', meal: 'เช้า'),
          green,
        );
        expect(replaced.cleanupIssue, isNull);
        expect(replaced.food.id, original.id);
        final newPath = run.service.objectPath(replaced.food.imageUrl)!;
        expect(newPath, isNot(oldPath));
        expect(await run.exists(oldPath), isTrue);
        expect((await run.service.deleteFood(same)).cleanupIssue, isNull);
        expect(await run.exists(oldPath), isTrue);
        expect((await run.service.deleteFood(alias)).cleanupIssue, isNull);
        expect(await run.exists(oldPath), isFalse);
        expect(
          (await run.trace.get(Uri.parse(replaced.food.imageUrl!))).bodyBytes,
          orderedEquals(green.bytes),
        );

        final invalidPath = 'foods/${run.tag.toLowerCase()}.png';
        await expectLater(
          run.files.uploadBinary(
            invalidPath,
            blue.bytes,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: false,
            ),
            retryAttempts: 0,
          ),
          throwsA(isA<StorageException>()),
        );
        expect(await run.exists(invalidPath), isFalse);

        await expectLater(
          run.files.uploadBinary(
            newPath,
            blue.bytes,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: true,
            ),
            retryAttempts: 0,
          ),
          throwsA(isA<StorageException>()),
        );
        expect(
          (await run.trace.get(Uri.parse(replaced.food.imageUrl!))).bodyBytes,
          orderedEquals(green.bytes),
        );

        for (final entry in <String, Object>{
          'id': const Uuid().v4(),
          'created_at': '2026-11-25T00:00:00Z',
        }.entries) {
          await expectLater(
            run.client.from(SupabaseService.table).insert({
              ..._input('${run.tag}-denied-${entry.key}').writeValues(null),
              entry.key: entry.value,
            }),
            throwsA(
              isA<PostgrestException>().having(
                (e) => e.code,
                'SQLSTATE',
                '42501',
              ),
            ),
          );
          await expectLater(
            run.client
                .from(SupabaseService.table)
                .update({entry.key: entry.value})
                .eq('id', empty.id)
                .eq('foodName', empty.input.name),
            throwsA(
              isA<PostgrestException>().having(
                (e) => e.code,
                'SQLSTATE',
                '42501',
              ),
            ),
          );
        }

        run.trace.rejectNextInsert = true;
        await expectLater(
          run.service.addFood(_input('${run.tag}-constraint'), blue),
          throwsA(
            isA<FoodActionException>().having(
              (e) => e.message,
              'message',
              'ฐานข้อมูลปฏิเสธการบันทึก',
            ),
          ),
        );
        expect(run.trace.constraintRejected, isTrue);
        expect(await run.exists(run.trace.uploads.last), isFalse);

        expect(
          (await run.service.deleteFood(replaced.food)).cleanupIssue,
          isNull,
        );
        expect(await run.exists(newPath), isFalse);
        expect((await run.service.deleteFood(empty)).cleanupIssue, isNull);
        expect(await run.read(), isEmpty);
        // เฉพาะหลักฐานสังเคราะห์ ไม่แสดง endpoint หรือ key
        debugPrintSynchronously(
          'LIVE CRUD, shared image references, Storage, CHECK and column grants verified',
        );
      } finally {
        await run.cleanup();
      }
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'live navigation reloads the list from Data API after return',
    (tester) async {
      final run = (await tester.runAsync(() async => _LiveRun()))!;
      final service = _ScopedLiveService(run);
      Future<void> resolveRead() async {
        final rows = await tester.runAsync(run.read);
        service.completeRead(rows!);
        await tester.pumpAndSettle();
      }

      try {
        await tester.pumpWidget(FoodTrackerApp(service: service));
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 450));
        expect(service.reads, 1);
        await resolveRead();
        await tester.tap(find.byTooltip('เพิ่มรายการอาหาร'));
        await tester.pumpAndSettle();
        expect(find.text('Food Tracker (เพิ่ม)'), findsOneWidget);

        await tester.runAsync(() async {
          run.record(
            (await run.service.addFood(
              _input('${run.tag}-refresh'),
              null,
            )).food,
          );
        });
        await tester.tap(find.byType(BackButton));
        await tester.pump(const Duration(milliseconds: 450));
        expect(service.reads, 2);
        await resolveRead();
        expect(find.text('กิน: ${run.tag}-refresh'), findsOneWidget);
        debugPrintSynchronously(
          'LIVE navigation refresh read the newly created synthetic row',
        );
      } finally {
        await tester.runAsync(() async {
          try {
            await run.cleanup();
          } finally {
            await run.close();
          }
        });
      }
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _LiveRun {
  _LiveRun() {
    if (!_url.startsWith('https://') || !_key.startsWith('sb_publishable_')) {
      throw StateError(
        'Live test requires ignored local publishable configuration',
      );
    }
    trace = _ScopedHttp(Uri.parse(_url), tag);
    client = SupabaseClient(
      _url,
      _key,
      httpClient: trace,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    service = SupabaseService(client, Uri.parse(_url));
  }

  final tag = 'A09-TEST-${const Uuid().v4()}';
  final ids = <String>{};
  late final _ScopedHttp trace;
  late final SupabaseClient client;
  late final SupabaseService service;
  StorageFileApi get files => client.storage.from(SupabaseService.bucket);

  void record(FoodTracker food) => ids.add(food.id);

  Future<FoodTracker> addImageReference(String suffix, String url) async {
    final row = await client
        .from(SupabaseService.table)
        .insert(_input('$tag-$suffix').writeValues(url))
        .select(SupabaseService.columns)
        .single();
    final food = FoodTracker.fromJson(row);
    record(food);
    return food;
  }

  Future<List<FoodTracker>> read() async {
    final rows = await client
        .from(SupabaseService.table)
        .select(SupabaseService.columns)
        .like('foodName', '$tag-%')
        .order('foodDate', ascending: false)
        .order('created_at', ascending: false)
        .order('id', ascending: false);
    return rows.map(FoodTracker.fromJson).toList();
  }

  Future<bool> _listed(String path) async {
    final name = path.split('/').last;
    final files = await this.files.list(
      path: 'foods',
      searchOptions: SearchOptions(search: name),
    );
    return files.any((file) => file.name == name);
  }

  Future<bool> _served(String path) async {
    final url = Uri.parse(files.getPublicUrl(path))
        .replace(queryParameters: {'cacheNonce': const Uuid().v4()});
    final response = await trace
        .get(url, headers: {'cache-control': 'no-cache, no-store'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) return true;
    if (response.statusCode == 404 || response.statusCode == 400) {
      try {
        final body = jsonDecode(response.body);
        if (body is Map &&
            (body['message'] == 'Object not found' ||
                body['error'] == 'NoSuchKey')) {
          return false;
        }
      } on FormatException {
        // A response without a Storage error body cannot confirm absence.
      }
    }
    throw StateError(
      'Public URL cannot confirm file status (HTTP ${response.statusCode}): $path',
    );
  }

  Future<bool> exists(String path) async {
    // A public read checks files hidden by the INSERT/SELECT policy mismatch.
    if (await _served(path)) return true;
    return _listed(path);
  }

  Future<void> cleanup() async {
    try {
      for (final food in await read()) {
        record(food);
        await client
            .from(SupabaseService.table)
            .delete()
            .eq('id', food.id)
            .eq('foodName', food.input.name);
      }
      for (final path in trace.uploads) {
        if (!await exists(path)) continue;
        if (service.objectPath(files.getPublicUrl(path)) != path) {
          throw StateError(
            'Unexpected test file outside DELETE policy; retained for Project Owner: $path',
          );
        }
        final bool referenced;
        try {
          referenced = await service.hasImageReference(path);
        } on Exception {
          throw StateError(
            'Could not confirm test file references; retained $path',
          );
        } on TypeError {
          throw StateError(
            'Could not confirm test file references; retained $path',
          );
        }
        if (referenced) {
          throw StateError('Test file still referenced; retained $path');
        }
        try {
          await files.remove([path]);
        } on Exception {
          throw StateError('Storage could not remove test file: $path');
        }
      }
      expect(await read(), isEmpty);
      for (final path in trace.uploads) {
        expect(
          await exists(path),
          isFalse,
          reason: 'Test file still visible at $path',
        );
      }
      debugPrintSynchronously('LIVE cleanup verified for $tag');
    } finally {
      debugPrintSynchronously(
        'LIVE evidence $tag row UUIDs: ${ids.join(', ')}',
      );
      debugPrintSynchronously(
        'LIVE evidence $tag attempted object paths: ${trace.uploads.join(', ')}',
      );
      debugPrintSynchronously(
        'LIVE evidence $tag confirmed files: ${trace.createdFiles.join(', ')}',
      );
      debugPrintSynchronously(
        'LIVE evidence $tag rejected storage writes: ${trace.rejectedWrites.join(', ')}',
      );
    }
  }

  Future<void> close() async {
    await client.dispose();
    trace.close();
  }
}

class _ScopedLiveService implements FoodService {
  _ScopedLiveService(this.run);

  final _LiveRun run;
  int reads = 0;
  late Completer<List<FoodTracker>> _pending;

  @override
  Future<List<FoodTracker>> fetchFoods() {
    reads++;
    _pending = Completer<List<FoodTracker>>();
    return _pending.future;
  }

  // The widget uses fake time. Resolve each requested read with real Data API
  // rows in tester.runAsync, then deliver them back to the original Future.
  void completeRead(List<FoodTracker> rows) => _pending.complete(rows);

  @override
  String? displayImage(String? url) => run.service.displayImage(url);

  @override
  Future<FoodChange> addFood(FoodInput input, FoodPhoto? photo) =>
      run.service.addFood(input, photo);

  @override
  Future<FoodChange> updateFood(
    FoodTracker original,
    FoodInput input,
    FoodPhoto? photo,
  ) => run.service.updateFood(original, input, photo);

  @override
  Future<FoodChange> deleteFood(FoodTracker original) =>
      run.service.deleteFood(original);
}

class _ScopedHttp extends http.BaseClient {
  _ScopedHttp(this.origin, this.tag);

  final Uri origin;
  final String tag;
  // Flutter's widget test binding installs a fake HttpClient. Use the real
  // transport only inside this opt-in test's request scope.
  final _inner = HttpOverrides.runWithHttpOverrides(
    http.Client.new,
    _LiveHttpOverrides(),
  );
  final uploads = <String>{};
  final createdFiles = <String>{};
  final rejectedWrites = <String>[];
  bool rejectNextInsert = false;
  bool constraintRejected = false;
  int dbWrites = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final parts = request.url.pathSegments;
    bool starts(List<String> prefix) =>
        parts.length >= prefix.length &&
        List.generate(
          prefix.length,
          (i) => parts[i] == prefix[i],
        ).every((same) => same);
    const bucket = SupabaseService.bucket;
    final table =
        starts(const ['rest', 'v1', SupabaseService.table]) &&
        parts.length == 3;
    final upload = starts(const ['storage', 'v1', 'object', bucket, 'foods']);
    final public = starts(const [
      'storage',
      'v1',
      'object',
      'public',
      bucket,
      'foods',
    ]);
    final list = starts(const ['storage', 'v1', 'object', 'list', bucket]);
    final remove =
        starts(const ['storage', 'v1', 'object', bucket]) && parts.length == 4;
    if (request.url.origin != origin.origin ||
        !(table || upload || public || list || remove)) {
      throw StateError('Test blocked a request outside Food Tracker');
    }
    final object = upload && request.method == 'POST'
        ? parts.skip(4).join('/')
        : null;
    if (object != null) uploads.add(object);
    if (table && request.method != 'GET') dbWrites++;
    final inject =
        table &&
        rejectNextInsert &&
        request is http.Request &&
        request.method == 'POST';
    if (inject) {
      rejectNextInsert = false;
      final values = jsonDecode(request.body) as Map<String, dynamic>;
      if (!(values['foodName'] as String).startsWith('$tag-')) {
        throw StateError('Test stopped a write outside the synthetic record');
      }
      request.body = jsonEncode(values..['foodMeal'] = 'invalid-meal');
    }
    try {
      request.followRedirects = false;
      final response = await _inner.send(request);
      if (object != null) {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          // An accepted overwrite changes a known file and creates no new path.
          if (request.headers['x-upsert'] != 'true') createdFiles.add(object);
        } else if (response.statusCode >= 400 && response.statusCode < 500) {
          final action = request.headers['x-upsert'] == 'true'
              ? 'overwrite'
              : 'upload';
          rejectedWrites.add('$action $object (HTTP ${response.statusCode})');
        }
      }
      if (inject) {
        final bytes = await response.stream.toBytes();
        if (response.statusCode >= 400) {
          final error = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
          constraintRejected = error['code'] == '23514';
        }
        return http.StreamedResponse(
          Stream.value(bytes),
          response.statusCode,
          headers: response.headers,
          request: response.request ?? request,
        );
      }
      return response;
    } on http.ClientException {
      throw http.ClientException('Food Tracker request failed');
    }
  }

  @override
  void close() => _inner.close();
}

class _LiveHttpOverrides extends HttpOverrides {}
