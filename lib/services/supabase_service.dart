import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/food_photo.dart';
import '../models/food_tracker.dart';
import 'food_service.dart';

class SupabaseService implements FoodService {
  SupabaseService(this._client, this._project);

  final SupabaseClient _client;
  final Uri _project;
  static const table = 'food_tracker_tb';
  static const bucket = 'food_tracker_bk';
  static const columns =
      'id,created_at,foodDate,foodMeal,foodName,foodPrice,foodPerson,foodImageUrl';
  static const _timeout = Duration(seconds: 18);
  static final _uuid = RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$');
  static final _path = RegExp(
    r'^foods/[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}[.](jpg|jpeg|png|webp)$',
  );

  @override
  Future<List<FoodTracker>> fetchFoods() async {
    final foods = <FoodTracker>[];
    const pageSize = 500;
    for (var offset = 0; ; offset += pageSize) {
      final rows = await _client
          .from(table)
          .select(columns)
          .order('foodDate', ascending: false)
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + pageSize - 1)
          .timeout(_timeout);
      foods.addAll(rows.map(FoodTracker.fromJson));
      if (rows.length < pageSize) return foods;
    }
  }

  @override
  Future<FoodChange> addFood(FoodInput input, FoodPhoto? photo) async {
    final values = input.writeValues(null);
    final uploaded = photo == null ? null : await _upload(photo);
    values['foodImageUrl'] = uploaded;
    final saved = await _save(
      () => _client.from(table).insert(values).select(columns),
      values,
      uploaded,
      () async => uploaded == null ? null : await _findByImage(uploaded),
    );
    return FoodChange(saved);
  }

  @override
  Future<FoodChange> updateFood(
    FoodTracker original,
    FoodInput input,
    FoodPhoto? photo,
  ) async {
    final id = _idOf(original);
    final oldUrl = original.imageUrl;
    final values = input.writeValues(
      oldUrl?.trim().isEmpty == true ? null : oldUrl,
    );
    final uploaded = photo == null ? null : await _upload(photo);
    if (uploaded != null) values['foodImageUrl'] = uploaded;
    final saved = await _save(
      () => _matchOriginal(
        _client.from(table).update(values).eq('id', id),
        original,
      ).select(columns),
      values,
      uploaded,
      () => _findById(id),
    );
    return FoodChange(
      saved,
      cleanupIssue: uploaded == null ? null : await _cleanup(oldUrl),
    );
  }

  @override
  Future<FoodChange> deleteFood(FoodTracker original) async {
    final id = _idOf(original);
    FoodTracker? removed;
    try {
      final rows = await _matchOriginal(
        _client.from(table).delete().eq('id', id),
        original,
      ).select(columns).timeout(_timeout);
      if (rows.length == 1) removed = FoodTracker.fromJson(rows.single);
    } on PostgrestException catch (error) {
      if (_rejected(error)) {
        throw const FoodActionException('ฐานข้อมูลปฏิเสธการลบ');
      }
      if (await _isAbsent(id)) removed = original;
    } on Exception {
      if (await _isAbsent(id)) removed = original;
    } on TypeError {
      if (await _isAbsent(id)) removed = original;
    }
    if (removed == null) {
      throw const FoodActionException(
        'ยืนยันการลบไม่ได้ กรุณาตรวจรายการล่าสุด',
        refresh: true,
      );
    }
    return FoodChange(removed, cleanupIssue: await _cleanup(removed.imageUrl));
  }

  String _idOf(FoodTracker food) {
    if (!_uuid.hasMatch(food.id)) {
      throw const FoodActionException('รหัสรายการผิดรูปแบบ', refresh: true);
    }
    return food.id;
  }

  // ตรวจ UUID และค่าที่โหลดมาในคำขอเดียวกับการเขียน
  PostgrestFilterBuilder<T> _matchOriginal<T>(
    PostgrestFilterBuilder<T> query,
    FoodTracker original,
  ) {
    for (final entry in original.userValues.entries) {
      final value = entry.value;
      query = value == null
          ? query.isFilter(entry.key, null)
          : query.eq(entry.key, value);
    }
    return query;
  }

  Future<FoodTracker> _save(
    Future<List<Map<String, dynamic>>> Function() write,
    Map<String, Object?> values,
    String? uploaded,
    Future<FoodTracker?> Function() verify,
  ) async {
    List<Map<String, dynamic>> rows;
    try {
      rows = await write().timeout(_timeout);
    } on PostgrestException catch (error) {
      if (_rejected(error)) {
        final pending = await _cleanup(uploaded);
        throw FoodActionException(
          _withCleanupNotice('ฐานข้อมูลปฏิเสธการบันทึก', pending),
        );
      }
      return _verifySave(verify, values, uploaded);
    } on Exception {
      return _verifySave(verify, values, uploaded);
    } on TypeError {
      return _verifySave(verify, values, uploaded);
    }
    if (rows.isEmpty) {
      final pending = await _cleanup(uploaded);
      throw FoodActionException(
        _withCleanupNotice(
          'รายการเปลี่ยนไปแล้ว กรุณาตรวจรายการล่าสุด',
          pending,
        ),
        refresh: true,
      );
    }
    if (rows.length == 1) {
      try {
        final row = FoodTracker.fromJson(rows.single);
        if (_matches(row, values)) return row;
      } on FormatException {
        // อ่านยืนยันซ้ำก่อนสรุปผลการเขียน
      } on TypeError {
        // อ่านยืนยันซ้ำก่อนสรุปผลการเขียน
      }
    }
    return _verifySave(verify, values, uploaded);
  }

  bool _rejected(PostgrestException error) =>
      RegExp(r'^(22|23|42)[A-Z0-9]{3}$').hasMatch(error.code ?? '');

  bool _matches(FoodTracker food, Map<String, Object?> values) {
    final current = food.userValues;
    return values.entries.every((entry) => current[entry.key] == entry.value);
  }

  Future<FoodTracker> _verifySave(
    Future<FoodTracker?> Function() verify,
    Map<String, Object?> values,
    String? uploaded,
  ) async {
    try {
      final row = await verify();
      if (row != null && _matches(row, values)) return row;
    } on Exception {
      // เก็บรูปไว้จนกว่าจะทราบผล
    } on TypeError {
      // เก็บรูปไว้จนกว่าจะทราบผล
    }
    throw FoodActionException(
      _withCleanupNotice(
        'ยืนยันการบันทึกไม่ได้ กรุณาตรวจรายการก่อนบันทึกซ้ำ',
        uploaded == null
            ? null
            : FoodCleanupIssue(
                'เก็บรูปไว้จนกว่าจะยืนยันผล',
                objectPath: objectPath(uploaded),
              ),
      ),
      refresh: true,
    );
  }

  Future<FoodTracker?> _findById(String id) async {
    final row = await _client
        .from(table)
        .select(columns)
        .eq('id', id)
        .maybeSingle()
        .timeout(_timeout);
    return row == null ? null : FoodTracker.fromJson(row);
  }

  Future<FoodTracker?> _findByImage(String url) async {
    final rows = await _client
        .from(table)
        .select(columns)
        .eq('foodImageUrl', url)
        .limit(2)
        .timeout(_timeout);
    return rows.length == 1 ? FoodTracker.fromJson(rows.single) : null;
  }

  Future<bool> _isAbsent(String id) async {
    try {
      return await _findById(id) == null;
    } on Exception {
      return false;
    } on TypeError {
      return false;
    }
  }

  Future<String> _upload(FoodPhoto photo) async {
    final path = 'foods/${const Uuid().v4()}.${photo.extension}';
    final storage = _client.storage.from(bucket);
    try {
      await storage
          .uploadBinary(
            path,
            photo.bytes,
            fileOptions: FileOptions(
              contentType: photo.mimeType,
              upsert: false,
            ),
            retryAttempts: 0,
          )
          .timeout(_timeout);
    } on StorageException {
      throw FoodActionException(
        'Storage อัปโหลดรูปไม่สำเร็จ กรุณาตรวจไฟล์ $path',
      );
    } on Exception {
      throw FoodActionException('ยืนยันผลอัปโหลดไม่ได้ กรุณาตรวจไฟล์ $path');
    }
    return storage.getPublicUrl(path);
  }

  String? objectPath(String? url) {
    if (url == null || _project.scheme != 'https') return null;
    final prefix = _publicPrefix;
    if (!url.startsWith(prefix)) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.origin != _project.origin || uri.hasFragment) {
      return null;
    }
    final query = url.indexOf('?');
    final path = url.substring(prefix.length, query == -1 ? url.length : query);
    return _path.stringMatch(path) == path ? path : null;
  }

  String get _publicPrefix =>
      '${_project.origin}/storage/v1/object/public/$bucket/';

  @override
  String? displayImage(String? url) {
    final path = objectPath(url);
    return path == null ? null : '$_publicPrefix$path';
  }

  String _withCleanupNotice(String message, FoodCleanupIssue? issue) =>
      issue == null ? message : '$message • ${issue.notice}';

  // Reference check และ remove เป็นคนละคำขอ
  Future<FoodCleanupIssue?> _cleanup(String? url) async {
    if (url == null || url.trim().isEmpty) return null;
    final path = objectPath(url);
    if (path == null) return const FoodCleanupIssue('URL รูปเดิมนอกขอบเขต');

    try {
      if (await hasImageReference(path)) return null;
    } on Exception {
      return FoodCleanupIssue(
        'ยืนยันการอ้างอิงรูปไม่ได้ จึงเก็บไฟล์ไว้',
        objectPath: path,
      );
    } on TypeError {
      return FoodCleanupIssue(
        'ข้อมูลอ้างอิงรูปผิดรูปแบบ จึงเก็บไฟล์ไว้',
        objectPath: path,
      );
    }

    final pending = FoodCleanupIssue('ยืนยันการลบรูปไม่ได้', objectPath: path);
    try {
      final removed = await _client.storage
          .from(bucket)
          .remove([path])
          .timeout(_timeout);
      return removed.any((file) => file.name == path) ? null : pending;
    } on Exception {
      return pending;
    } on TypeError {
      return pending;
    }
  }

  Future<bool> hasImageReference(String path) async {
    if (_path.stringMatch(path) != path) {
      throw const FormatException('พาธไฟล์ผิดรูปแบบ');
    }
    String? lastId;
    while (true) {
      var query = _client
          .from(table)
          .select('id,foodImageUrl')
          .not('foodImageUrl', 'is', null);
      final cursor = lastId;
      if (cursor != null) query = query.gt('id', cursor);
      final rows = await query
          .order('id', ascending: true)
          .limit(100)
          .timeout(_timeout);
      // API อาจคืนแถวต่ำกว่า limit จึงเลื่อน cursor จนได้หน้าว่าง
      if (rows.isEmpty) return false;
      for (final row in rows) {
        final id = row['id'] as String;
        final prior = lastId;
        if (_uuid.stringMatch(id) != id ||
            (prior != null && id.compareTo(prior) <= 0)) {
          throw const FormatException('ลำดับข้อมูลอ้างอิงรูปผิดรูปแบบ');
        }
        lastId = id;
        if (_referencePath(row['foodImageUrl'] as String) == path) return true;
      }
    }
  }

  // ใช้ URL แบบถอดรหัสเพื่อปกป้องไฟล์เท่านั้น พาธสำหรับลบยังใช้ objectPath
  String? _referencePath(String url) {
    final text = url.trim();
    final uri = Uri.tryParse(text);
    if (uri == null) {
      if (text.startsWith('${_project.origin}/')) {
        throw const FormatException('URL อ้างอิงรูปผิดรูปแบบ');
      }
      return null;
    }
    if (uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.origin != _project.origin) {
      return null;
    }

    // pathSegments ถอดรหัสหนึ่งครั้ง และแยก query กับ fragment ออกจากพาธ
    const prefix = 'storage/v1/object/public/$bucket/';
    final decoded = uri.pathSegments.join('/');
    if (!decoded.startsWith(prefix)) return null;
    final path = decoded.substring(prefix.length);
    if (path.contains('%') || path.contains(r'\')) {
      throw const FormatException('ยืนยันพาธอ้างอิงรูปไม่ได้');
    }
    return _path.stringMatch(path) == path ? path : null;
  }
}
