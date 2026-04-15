import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminDashboardService {
  AdminDashboardService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String barangayTable = 'barangay';
  static const String collectionLogsTable = 'collection_logs';
  static const String collectionSchedulesTable = 'collection_schedules';
  static const String usersTable = 'users';
  static const String wasteReportsTable = 'waste_reports';
  static const List<String> reportPhotoBuckets = <String>[
    'waste-report-photos',
    'waste_reports',
    'waste-report',
    'reports',
    'uploads',
    'waste-images',
  ];
  static const List<String> collectionPhotoBuckets = <String>[
    'collection-photos',
    'garbage-collection-photos',
    'waste-report-photos',
    'waste_reports',
    'reports',
    'uploads',
    'waste-images',
  ];

  Future<List<BarangaySummary>> fetchBarangaySummaries() async {
    final results = await Future.wait([
      _fetchBarangays(),
      _fetchCollectionLogs(),
      _fetchWasteReports(),
    ]);

    final barangays = results[0] as List<BarangayRow>;
    final logs = results[1] as List<CollectionLogItem>;
    final reports = results[2] as List<ResidentReportItem>;

    final groupedLogs = <int, List<CollectionLogItem>>{};
    for (final log in logs) {
      groupedLogs
          .putIfAbsent(log.barangayId, () => <CollectionLogItem>[])
          .add(log);
    }

    final reportCounts = <int, int>{};
    for (final report in reports) {
      if (report.userBarangayId == null) {
        continue;
      }
      reportCounts[report.userBarangayId!] =
          (reportCounts[report.userBarangayId!] ?? 0) + 1;
    }

    final summaries = barangays.map((barangay) {
      final barangayLogs =
          groupedLogs[barangay.id] ?? const <CollectionLogItem>[];
      final totalLogs = barangayLogs.length;
      final completedLogs = barangayLogs.where((log) => log.isCompleted).length;
      final pendingLogs = totalLogs - completedLogs;
      final complianceRate = totalLogs == 0
          ? 0.0
          : (completedLogs / totalLogs) * 100;
      final latestLog = barangayLogs.isEmpty ? null : barangayLogs.first;

      return BarangaySummary(
        id: barangay.id,
        name: barangay.name,
        district: barangay.district,
        city: barangay.city,
        totalLogs: totalLogs,
        completedLogs: completedLogs,
        pendingLogs: pendingLogs,
        reportCount: reportCounts[barangay.id] ?? 0,
        complianceRate: complianceRate,
        latestStatus: latestLog?.status ?? 'No logs yet',
        latestUpdate: latestLog?.referenceDate,
      );
    }).toList();

    summaries.sort((a, b) {
      final complianceCompare = b.complianceRate.compareTo(a.complianceRate);
      if (complianceCompare != 0) {
        return complianceCompare;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return summaries;
  }

  Future<List<CollectionLogItem>> fetchBarangayLogs(int barangayId) async {
    final rawRows = await _client
        .from(collectionLogsTable)
        .select(
          'id, barangay_id, schedule_id, collection_date, status, remarks, created_at, barangay:barangay_id(id, name, district, city), schedule:collection_schedules!collection_logs_schedule_id_fkey(id, day_of_week, start_time, end_time, waste_type)',
        )
        .eq('barangay_id', barangayId)
        .order('collection_date', ascending: false);

    return _parseCollectionLogs(rawRows);
  }

  Future<List<ResidentReportItem>> fetchResidentReports(int barangayId) async {
    final rawRows = await _client
        .from(wasteReportsTable)
        .select(
          'id, user_id, schedule_id, photo_path, photo_url, latitude, longitude, address_text, description, status, reviewed_by, review_notes, created_at, updated_at, user:users!waste_reports_user_id_fkey(id, full_name, email, phone, role, barangay_id, address, email, phone), schedule:collection_schedules!waste_reports_schedule_id_fkey(id, barangay_id, day_of_week, start_time, end_time, waste_type, notes, is_active)',
        )
        .order('created_at', ascending: false);

    return _parseResidentReports(
      rawRows,
    ).where((report) => report.userBarangayId == barangayId).toList();
  }

  Future<List<CollectionScheduleItem>> fetchSchedules(int barangayId) async {
    final rawRows = await _client
        .from(collectionSchedulesTable)
        .select(
          'id, barangay_id, day_of_week, start_time, end_time, waste_type, notes, is_active, created_by, created_at, barangay:barangay_id(id, name, district, city)',
        )
        .eq('barangay_id', barangayId)
        .order('day_of_week', ascending: true)
        .order('start_time', ascending: true);

    return _parseSchedules(rawRows);
  }

  Future<List<CollectionLogItem>> fetchRecentCollectionLogs({
    int limit = 5,
  }) async {
    final rawRows = await _client
        .from(collectionLogsTable)
        .select(
          'id, barangay_id, schedule_id, collection_date, status, remarks, created_at, barangay:barangay_id(id, name, district, city), schedule:collection_schedules!collection_logs_schedule_id_fkey(id, day_of_week, start_time, end_time, waste_type)',
        )
        .order('collection_date', ascending: false)
        .limit(limit);

    return _parseCollectionLogs(rawRows);
  }

  Future<List<CollectionScheduleItem>> fetchActiveSchedules({
    int limit = 5,
  }) async {
    final rawRows = await _client
        .from(collectionSchedulesTable)
        .select(
          'id, barangay_id, day_of_week, start_time, end_time, waste_type, notes, is_active, created_by, created_at, barangay:barangay_id(id, name, district, city)',
        )
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .limit(limit);

    return _parseSchedules(rawRows);
  }

  Future<List<ResidentReportItem>> fetchRecentReports({int limit = 5}) async {
    final rawRows = await _client
        .from(wasteReportsTable)
        .select(
          'id, user_id, schedule_id, photo_path, photo_url, latitude, longitude, address_text, description, status, reviewed_by, review_notes, created_at, updated_at, user:users!waste_reports_user_id_fkey(id, full_name, email, phone, role, barangay_id, address, email, phone), schedule:collection_schedules!waste_reports_schedule_id_fkey(id, barangay_id, day_of_week, start_time, end_time, waste_type, notes, is_active)',
        )
        .order('created_at', ascending: false)
        .limit(limit);

    return _parseResidentReports(rawRows);
  }

  Future<CurrentUserProfile> fetchCurrentUserProfile() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      throw const AuthException('No authenticated user session found.');
    }

    await _ensureCurrentUserProfileRow(authUser);

    final profileRow = await _client
        .from(usersTable)
        .select(
          'id, full_name, email, phone, role, address, barangay_id, created_at',
        )
        .eq('id', authUser.id)
        .maybeSingle();

    final row = profileRow is Map<String, dynamic>
        ? profileRow
        : <String, dynamic>{};

    final userId = _readString(row, const ['id'], fallback: authUser.id);
    final barangayId = _readInt(row, const ['barangay_id']);

    String barangayName = '';
    String barangayDistrict = '';
    String barangayCity = '';
    if (barangayId != null) {
      try {
        final barangayRow = await _client
            .from(barangayTable)
            .select('name, district, city')
            .eq('id', barangayId)
            .maybeSingle();
        if (barangayRow is Map<String, dynamic>) {
          barangayName = _readString(barangayRow, const ['name']);
          barangayDistrict = _readString(barangayRow, const ['district']);
          barangayCity = _readString(barangayRow, const ['city']);
        }
      } catch (_) {
        // Continue with remaining profile data when barangay lookup is unavailable.
      }
    }

    final metadata = authUser.userMetadata ?? const <String, dynamic>{};

    return CurrentUserProfile(
      id: userId,
      fullName: _readString(
        row,
        const ['full_name'],
        fallback: _readString(metadata, const [
          'full_name',
          'name',
        ], fallback: 'User'),
      ),
      email: _readString(row, const ['email'], fallback: authUser.email ?? ''),
      phone: _readString(row, const [
        'phone',
      ], fallback: _readString(metadata, const ['phone'])),
      role: _readString(row, const [
        'role',
      ], fallback: _readString(metadata, const ['role'], fallback: 'admin')),
      address: _readString(row, const ['address']),
      barangayId: barangayId,
      barangayName: barangayName,
      barangayDistrict: barangayDistrict,
      barangayCity: barangayCity,
      createdAt:
          _readDateTime(row, const ['created_at']) ??
          DateTime.tryParse(authUser.createdAt),
      updatedAt: authUser.updatedAt != null
          ? DateTime.tryParse(authUser.updatedAt!)
          : null,
    );
  }

  Future<void> updateCurrentUserProfile({
    required String phone,
    required String address,
    int? barangayId,
  }) async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      throw const AuthException('No authenticated user session found.');
    }

    final payload = <String, dynamic>{
      'phone': phone.trim(),
      'address': address.trim(),
      'barangay_id': barangayId,
    };

    await _client.from(usersTable).update(payload).eq('id', authUser.id);
  }

  Future<List<BarangayRow>> fetchBarangayOptions() async {
    return _fetchBarangays();
  }

  Future<String?> resolveReportPhotoUrl(ResidentReportItem report) async {
    if (report.photoUrl.isNotEmpty) {
      return report.photoUrl;
    }

    if (report.photoPath.isEmpty) {
      return null;
    }

    if (report.photoPath.startsWith('http://') ||
        report.photoPath.startsWith('https://')) {
      return report.photoPath;
    }

    final parsedPath = _parseStoragePathAndBucket(report.photoPath);
    final normalizedPath = parsedPath.path;
    final candidateBuckets = <String>{
      if (parsedPath.bucket.isNotEmpty) parsedPath.bucket,
      ...reportPhotoBuckets,
    };

    for (final bucket in candidateBuckets) {
      try {
        final signedUrl = await _client.storage
            .from(bucket)
            .createSignedUrl(normalizedPath, 60 * 30);
        if (signedUrl.isNotEmpty) {
          return signedUrl;
        }
      } catch (_) {
        try {
          final publicUrl = _client.storage
              .from(bucket)
              .getPublicUrl(normalizedPath);
          if (publicUrl.isNotEmpty) {
            return publicUrl;
          }
        } catch (_) {
          continue;
        }
      }
    }

    return null;
  }

  Future<List<String>> fetchCollectionPhotos({int limit = 6}) async {
    final photos = <String>[];

    for (final bucket in collectionPhotoBuckets) {
      if (photos.length >= limit) {
        break;
      }

      try {
        final objects = await _client.storage
            .from(bucket)
            .list(searchOptions: const SearchOptions(limit: 100));

        for (final object in objects) {
          if (photos.length >= limit) {
            break;
          }

          final name = object.name.trim();
          if (!_looksLikeImage(name)) {
            continue;
          }

          final path = _normalizeStoragePath(name);
          try {
            final signedUrl = await _client.storage
                .from(bucket)
                .createSignedUrl(path, 60 * 30);
            if (signedUrl.isNotEmpty) {
              photos.add(signedUrl);
              continue;
            }
          } catch (_) {
            // Fall back to public URL if signed URL is unavailable.
          }

          try {
            final publicUrl = _client.storage.from(bucket).getPublicUrl(path);
            if (publicUrl.isNotEmpty) {
              photos.add(publicUrl);
            }
          } catch (_) {
            continue;
          }
        }
      } catch (_) {
        continue;
      }
    }

    return photos;
  }

  Future<void> updateSchedule({
    required CollectionScheduleItem schedule,
    String? dayOfWeek,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    String? wasteType,
    String? notes,
    bool? isActive,
  }) async {
    final payload = <String, dynamic>{};

    if (dayOfWeek != null && dayOfWeek.trim().isNotEmpty) {
      payload['day_of_week'] = dayOfWeek.trim();
    }
    if (startTime != null) {
      payload['start_time'] = _timeOfDayToDatabaseValue(startTime);
    }
    if (endTime != null) {
      payload['end_time'] = _timeOfDayToDatabaseValue(endTime);
    }
    if (wasteType != null && wasteType.trim().isNotEmpty) {
      payload['waste_type'] = wasteType.trim();
    }
    if (notes != null) {
      payload['notes'] = notes.trim();
    }
    if (isActive != null) {
      payload['is_active'] = isActive;
    }

    if (payload.isEmpty) {
      return;
    }

    await _client
        .from(collectionSchedulesTable)
        .update(payload)
        .eq('id', schedule.id);
  }

  Future<void> updateScheduleStatus({
    required dynamic scheduleId,
    required bool isActive,
  }) async {
    await _client
        .from(collectionSchedulesTable)
        .update({'is_active': isActive})
        .eq('id', scheduleId);
  }

  Future<void> updateCollectionLogStatus({
    required dynamic logId,
    required String status,
  }) async {
    await _client
        .from(collectionLogsTable)
        .update({'status': status.trim().toLowerCase()})
        .eq('id', logId);
  }

  Future<void> updateResidentReportStatus({
    required dynamic reportId,
    required String status,
    String? reviewNotes,
  }) async {
    final normalizedStatus = status.trim().toLowerCase();
    final payload = <String, dynamic>{
      'status': normalizedStatus,
      'review_notes': reviewNotes?.trim(),
      'reviewed_by': _client.auth.currentUser?.id,
    };

    await _client.from(wasteReportsTable).update(payload).eq('id', reportId);
  }

  Future<void> deleteSchedule({required dynamic scheduleId}) async {
    await _client.from(collectionSchedulesTable).delete().eq('id', scheduleId);
  }

  Future<void> createSchedule({
    required int barangayId,
    required String dayOfWeek,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required String wasteType,
    String? notes,
    bool isActive = true,
  }) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw const AuthException(
        'Please log in again before creating a schedule.',
      );
    }

    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      throw const AuthException('No authenticated user session found.');
    }
    await _ensureCurrentUserProfileRow(authUser);

    final payload = <String, dynamic>{
      'barangay_id': barangayId,
      'day_of_week': dayOfWeek.trim(),
      'start_time': _timeOfDayToDatabaseValue(startTime),
      'end_time': _timeOfDayToDatabaseValue(endTime),
      'waste_type': wasteType.trim(),
      'notes': notes?.trim(),
      'is_active': isActive,
      'created_by': currentUserId,
    };

    await _client.from(collectionSchedulesTable).insert(payload).select('id');
  }

  Future<void> _ensureCurrentUserProfileRow(User authUser) async {
    final existing = await _client
        .from(usersTable)
        .select('id')
        .eq('id', authUser.id)
        .maybeSingle();

    if (existing is Map<String, dynamic>) {
      return;
    }

    final metadata = authUser.userMetadata ?? const <String, dynamic>{};
    final payload = <String, dynamic>{
      'id': authUser.id,
      'email': authUser.email ?? '${authUser.id}@placeholder.local',
      'full_name': _readString(metadata, const [
        'full_name',
        'name',
      ], fallback: 'Administrator'),
      'phone': _readString(metadata, const ['phone'], fallback: 'N/A'),
      'address': _readString(metadata, const ['address']),
      'role': _readString(metadata, const ['role'], fallback: 'admin'),
    };

    payload.removeWhere((key, value) => value == null);

    try {
      await _client.from(usersTable).insert(payload);
    } on PostgrestException catch (error) {
      final message = error.message;

      if (message.contains('users_email_key')) {
        final fallbackPayload = <String, dynamic>{
          ...payload,
          'email': '${authUser.id}@placeholder.local',
        };
        await _client
            .from(usersTable)
            .upsert(fallbackPayload, onConflict: 'id');
        return;
      }

      if (message.contains('duplicate key value') &&
          message.contains('users_pkey')) {
        return;
      }

      rethrow;
    }
  }

  Future<List<BarangayRow>> _fetchBarangays() async {
    final rawRows = await _client
        .from(barangayTable)
        .select('id, name, district, city')
        .order('name', ascending: true);

    return _parseBarangays(rawRows);
  }

  Future<List<CollectionLogItem>> _fetchCollectionLogs() async {
    final rawRows = await _client
        .from(collectionLogsTable)
        .select(
          'id, barangay_id, schedule_id, collection_date, status, remarks, created_at, barangay:barangay_id(id, name, district, city), schedule:collection_schedules!collection_logs_schedule_id_fkey(id, day_of_week, start_time, end_time, waste_type)',
        )
        .order('collection_date', ascending: false);

    return _parseCollectionLogs(rawRows);
  }

  Future<List<ResidentReportItem>> _fetchWasteReports() async {
    final rawRows = await _client
        .from(wasteReportsTable)
        .select(
          'id, user_id, schedule_id, photo_path, photo_url, latitude, longitude, address_text, description, status, reviewed_by, review_notes, created_at, updated_at, user:users!waste_reports_user_id_fkey(id, full_name, email, phone, role, barangay_id, address, email, phone), schedule:collection_schedules!waste_reports_schedule_id_fkey(id, barangay_id, day_of_week, start_time, end_time, waste_type, notes, is_active)',
        )
        .order('created_at', ascending: false);

    return _parseResidentReports(rawRows);
  }

  List<BarangayRow> _parseBarangays(dynamic rawRows) {
    return _parseRows(rawRows, (row) {
      return BarangayRow(
        id: _readInt(row, const ['id'])!,
        name: _readString(row, const ['name'], fallback: 'Unnamed barangay'),
        district: _readString(row, const ['district']),
        city: _readString(row, const ['city'], fallback: 'Davao City'),
      );
    });
  }

  List<CollectionLogItem> _parseCollectionLogs(dynamic rawRows) {
    return _parseRows(rawRows, (row) {
      final barangay = _readMap(row, const ['barangay']);
      final schedule = _readMap(row, const ['schedule']);
      return CollectionLogItem(
        id: row['id'],
        barangayId: _readInt(row, const ['barangay_id']) ?? 0,
        scheduleId: _readInt(row, const ['schedule_id']) ?? 0,
        barangayName: _readString(barangay, const [
          'name',
        ], fallback: 'Barangay'),
        barangayDistrict: _readString(barangay, const ['district']),
        barangayCity: _readString(barangay, const [
          'city',
        ], fallback: 'Davao City'),
        collectionDate:
            _readDateTime(row, const ['collection_date']) ?? DateTime.now(),
        status: _readString(row, const ['status'], fallback: 'Pending'),
        remarks: _readString(row, const ['remarks']),
        createdAt: _readDateTime(row, const ['created_at']),
        scheduleDayOfWeek: _readString(schedule, const ['day_of_week']),
        scheduleStartTime: _readTimeOfDay(schedule, const ['start_time']),
        scheduleEndTime: _readTimeOfDay(schedule, const ['end_time']),
        scheduleWasteType: _readString(schedule, const ['waste_type']),
      );
    });
  }

  List<ResidentReportItem> _parseResidentReports(dynamic rawRows) {
    return _parseRows(rawRows, (row) {
      final user = _readMap(row, const ['user']);
      final schedule = _readMap(row, const ['schedule']);
      return ResidentReportItem(
        id: row['id'],
        userBarangayId: _readInt(user, const ['barangay_id']),
        userId: _readString(row, const ['user_id']),
        residentName: _readString(user, const [
          'full_name',
        ], fallback: 'Resident'),
        email: _readString(user, const ['email']),
        phone: _readString(user, const ['phone']),
        address: _readString(user, const ['address']),
        role: _readString(user, const ['role']),
        photoPath: _readString(row, const ['photo_path']),
        photoUrl: _readString(row, const ['photo_url']),
        latitude: _readDouble(row, const ['latitude']),
        longitude: _readDouble(row, const ['longitude']),
        addressText: _readString(row, const ['address_text']),
        description: _readString(row, const ['description']),
        status: _readString(row, const ['status'], fallback: 'Pending'),
        reviewedBy: _readString(row, const ['reviewed_by']),
        reviewNotes: _readString(row, const ['review_notes']),
        createdAt: _readDateTime(row, const ['created_at']),
        updatedAt: _readDateTime(row, const ['updated_at']),
        scheduleDayOfWeek: _readString(schedule, const ['day_of_week']),
        scheduleStartTime: _readTimeOfDay(schedule, const ['start_time']),
        scheduleEndTime: _readTimeOfDay(schedule, const ['end_time']),
        scheduleWasteType: _readString(schedule, const ['waste_type']),
        scheduleNotes: _readString(schedule, const ['notes']),
        scheduleActive: _readBool(schedule, const ['is_active']) ?? true,
      );
    });
  }

  List<CollectionScheduleItem> _parseSchedules(dynamic rawRows) {
    return _parseRows(rawRows, (row) {
      final barangay = _readMap(row, const ['barangay']);
      return CollectionScheduleItem(
        id: row['id'],
        barangayId: _readInt(row, const ['barangay_id']) ?? 0,
        barangayName: _readString(barangay, const [
          'name',
        ], fallback: 'Barangay'),
        district: _readString(barangay, const ['district']),
        city: _readString(barangay, const ['city'], fallback: 'Davao City'),
        dayOfWeek: _readString(row, const ['day_of_week']),
        startTime: _readTimeOfDay(row, const ['start_time']),
        endTime: _readTimeOfDay(row, const ['end_time']),
        wasteType: _readString(row, const ['waste_type']),
        notes: _readString(row, const ['notes']),
        isActive: _readBool(row, const ['is_active']) ?? true,
        createdAt: _readDateTime(row, const ['created_at']),
      );
    });
  }

  List<T> _parseRows<T>(
    dynamic rawRows,
    T Function(Map<String, dynamic>) parser,
  ) {
    if (rawRows is! List) {
      return const [];
    }

    return rawRows
        .whereType<Map>()
        .map(
          (row) =>
              parser(Map<String, dynamic>.from(row.cast<String, dynamic>())),
        )
        .toList();
  }

  Map<String, dynamic> _readMap(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value is Map) {
        return Map<String, dynamic>.from(value.cast<String, dynamic>());
      }
    }

    return const <String, dynamic>{};
  }

  String _readString(
    Map<String, dynamic> row,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) {
        continue;
      }

      final text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }

    return fallback;
  }

  int? _readInt(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) {
        continue;
      }

      if (value is int) {
        return value;
      }

      return int.tryParse(value.toString());
    }

    return null;
  }

  double? _readDouble(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) {
        continue;
      }

      if (value is double) {
        return value;
      }

      if (value is int) {
        return value.toDouble();
      }

      return double.tryParse(value.toString());
    }

    return null;
  }

  bool? _readBool(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) {
        continue;
      }

      if (value is bool) {
        return value;
      }

      final text = value.toString().toLowerCase();
      if (text == 'true' || text == '1') {
        return true;
      }
      if (text == 'false' || text == '0') {
        return false;
      }
    }

    return null;
  }

  DateTime? _readDateTime(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) {
        continue;
      }

      if (value is DateTime) {
        return value;
      }

      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value);
      }
    }

    return null;
  }

  TimeOfDay? _readTimeOfDay(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) {
        continue;
      }

      final text = value.toString().trim();
      if (text.isEmpty) {
        continue;
      }

      final parts = text.split(':');
      if (parts.length < 2) {
        continue;
      }

      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) {
        continue;
      }

      return TimeOfDay(hour: hour, minute: minute);
    }

    return null;
  }

  String _timeOfDayToDatabaseValue(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute:00';
  }

  String _normalizeStoragePath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme && uri.path.isNotEmpty) {
      return uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    }

    return trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
  }

  ({String bucket, String path}) _parseStoragePathAndBucket(String value) {
    final normalized = _normalizeStoragePath(value);
    if (normalized.isEmpty) {
      return (bucket: '', path: normalized);
    }

    final segments = normalized
        .split('/')
        .where((it) => it.isNotEmpty)
        .toList();
    if (segments.length >= 4 &&
        segments[0] == 'storage' &&
        segments[1] == 'v1' &&
        segments[2] == 'object') {
      final start = segments[3] == 'public' || segments[3] == 'sign' ? 4 : 3;
      if (segments.length > start) {
        final bucket = segments[start];
        final path = segments.skip(start + 1).join('/');
        return (bucket: bucket, path: path);
      }
    }

    final bucketCandidates = <String>{
      ...reportPhotoBuckets,
      ...collectionPhotoBuckets,
    };
    final firstSlash = normalized.indexOf('/');
    if (firstSlash > 0) {
      final maybeBucket = normalized.substring(0, firstSlash);
      if (bucketCandidates.contains(maybeBucket)) {
        return (
          bucket: maybeBucket,
          path: normalized.substring(firstSlash + 1),
        );
      }
    }

    return (bucket: '', path: normalized);
  }

  bool _looksLikeImage(String value) {
    final lower = value.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }
}

class BarangayRow {
  const BarangayRow({
    required this.id,
    required this.name,
    required this.district,
    required this.city,
  });

  final int id;
  final String name;
  final String district;
  final String city;
}

class BarangaySummary {
  const BarangaySummary({
    required this.id,
    required this.name,
    required this.district,
    required this.city,
    required this.totalLogs,
    required this.completedLogs,
    required this.pendingLogs,
    required this.reportCount,
    required this.complianceRate,
    required this.latestStatus,
    required this.latestUpdate,
  });

  final int id;
  final String name;
  final String district;
  final String city;
  final int totalLogs;
  final int completedLogs;
  final int pendingLogs;
  final int reportCount;
  final double complianceRate;
  final String latestStatus;
  final DateTime? latestUpdate;
}

class CollectionLogItem {
  const CollectionLogItem({
    required this.id,
    required this.barangayId,
    required this.scheduleId,
    required this.barangayName,
    required this.barangayDistrict,
    required this.barangayCity,
    required this.collectionDate,
    required this.status,
    required this.remarks,
    required this.createdAt,
    required this.scheduleDayOfWeek,
    required this.scheduleStartTime,
    required this.scheduleEndTime,
    required this.scheduleWasteType,
  });

  final dynamic id;
  final int barangayId;
  final int scheduleId;
  final String barangayName;
  final String barangayDistrict;
  final String barangayCity;
  final DateTime collectionDate;
  final String status;
  final String remarks;
  final DateTime? createdAt;
  final String scheduleDayOfWeek;
  final TimeOfDay? scheduleStartTime;
  final TimeOfDay? scheduleEndTime;
  final String scheduleWasteType;

  bool get isCompleted {
    final normalized = status.toLowerCase();
    return normalized.contains('complete') ||
        normalized.contains('done') ||
        normalized.contains('finish');
  }

  bool get isPending => !isCompleted;

  DateTime get referenceDate => createdAt ?? collectionDate;
}

class ResidentReportItem {
  const ResidentReportItem({
    required this.id,
    required this.userBarangayId,
    required this.userId,
    required this.residentName,
    required this.email,
    required this.phone,
    required this.address,
    required this.role,
    required this.photoPath,
    required this.photoUrl,
    required this.latitude,
    required this.longitude,
    required this.addressText,
    required this.description,
    required this.status,
    required this.reviewedBy,
    required this.reviewNotes,
    required this.createdAt,
    required this.updatedAt,
    required this.scheduleDayOfWeek,
    required this.scheduleStartTime,
    required this.scheduleEndTime,
    required this.scheduleWasteType,
    required this.scheduleNotes,
    required this.scheduleActive,
  });

  final dynamic id;
  final int? userBarangayId;
  final String userId;
  final String residentName;
  final String email;
  final String phone;
  final String address;
  final String role;
  final String photoPath;
  final String photoUrl;
  final double? latitude;
  final double? longitude;
  final String addressText;
  final String description;
  final String status;
  final String reviewedBy;
  final String reviewNotes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String scheduleDayOfWeek;
  final TimeOfDay? scheduleStartTime;
  final TimeOfDay? scheduleEndTime;
  final String scheduleWasteType;
  final String scheduleNotes;
  final bool scheduleActive;

  bool get hasPhoto => photoUrl.isNotEmpty || photoPath.isNotEmpty;
}

class CollectionScheduleItem {
  const CollectionScheduleItem({
    required this.id,
    required this.barangayId,
    required this.barangayName,
    required this.district,
    required this.city,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.wasteType,
    required this.notes,
    required this.isActive,
    required this.createdAt,
  });

  final dynamic id;
  final int barangayId;
  final String barangayName;
  final String district;
  final String city;
  final String dayOfWeek;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final String wasteType;
  final String notes;
  final bool isActive;
  final DateTime? createdAt;
}

class CurrentUserProfile {
  const CurrentUserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    required this.address,
    required this.barangayId,
    required this.barangayName,
    required this.barangayDistrict,
    required this.barangayCity,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String role;
  final String address;
  final int? barangayId;
  final String barangayName;
  final String barangayDistrict;
  final String barangayCity;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}
