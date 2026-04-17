import 'dart:async';

import 'package:exam/services/admin_dashboard_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DetailsScreen extends StatefulWidget {
  const DetailsScreen({
    required this.barangayId,
    required this.barangayName,
    required this.district,
    required this.city,
    required this.onLogout,
    super.key,
  });

  final int barangayId;
  final String barangayName;
  final String district;
  final String city;
  final VoidCallback onLogout;

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  final AdminDashboardService _service = AdminDashboardService();
  static const int _initialVisibleCount = 3;
  static const double _backToTopOffset = 320;
  static const Duration _realtimeRefreshDebounceDuration = Duration(
    milliseconds: 300,
  );
  final List<RealtimeChannel> _realtimeChannels = <RealtimeChannel>[];
  Timer? _realtimeRefreshDebounce;
  static const List<String> _dayOfWeekOptions = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const List<String> _wasteTypeOptions = <String>[
    'Recyclable',
    'Biodegradable',
    'Non-Biodegradable',
  ];
  static const List<String> _collectionLogStatuses = <String>[
    'pending',
    'completed',
    'missed',
  ];
  static const List<String> _residentReportStatuses = <String>[
    'pending',
    'in_review',
    'resolved',
  ];

  late Future<List<CollectionLogItem>> _logsFuture;
  late Future<List<ResidentReportItem>> _reportsFuture;
  late Future<List<CollectionScheduleItem>> _schedulesFuture;
  late Future<List<String>> _collectionPhotosFuture;
  final Set<dynamic> _updatingReportIds = <dynamic>{};

  String _logsQuery = '';
  String _logsFilter = 'All';
  bool _showAllLogs = false;
  final TextEditingController _logsSearchController = TextEditingController();

  String _reportsQuery = '';
  String _reportsFilter = 'All';
  bool _showAllReports = false;
  final TextEditingController _reportsSearchController =
      TextEditingController();

  String _schedulesQuery = '';
  String _schedulesFilter = 'All';
  bool _showAllSchedules = false;
  final TextEditingController _schedulesSearchController =
      TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    _reloadData();
    _subscribeToRealtimeChanges();
    _scrollController.addListener(_onScrollChanged);
  }

  void _reloadData() {
    _logsFuture = _service.fetchBarangayLogs(widget.barangayId);
    _reportsFuture = _service.fetchResidentReports(widget.barangayId);
    _schedulesFuture = _service.fetchSchedules(widget.barangayId);
    _collectionPhotosFuture = _service.fetchCollectionPhotos(
      barangayId: widget.barangayId,
      limit: 8,
    );
  }

  Future<void> _refreshAll() async {
    setState(_reloadData);
    await Future.wait([
      _logsFuture,
      _reportsFuture,
      _schedulesFuture,
      _collectionPhotosFuture,
    ]);
  }

  Future<void> _refreshSchedules() async {
    setState(() {
      _schedulesFuture = _service.fetchSchedules(widget.barangayId);
    });
    await _schedulesFuture;
  }

  Future<void> _refreshLogs() async {
    setState(() {
      _logsFuture = _service.fetchBarangayLogs(widget.barangayId);
    });
    await _logsFuture;
  }

  Future<void> _refreshReports() async {
    setState(() {
      _reportsFuture = _service.fetchResidentReports(widget.barangayId);
    });
    await _reportsFuture;
  }

  Future<void> _updateCollectionLogStatus(
    CollectionLogItem log,
    String status,
  ) async {
    try {
      await _service.updateCollectionLogStatus(logId: log.id, status: status);
      if (!mounted) {
        return;
      }
      await _refreshLogs();
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message.isNotEmpty
                ? error.message
                : 'Unable to update collection log status.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to update collection log status: $error'),
        ),
      );
    }
  }

  Future<void> _openCollectionLogForm() async {
    final schedules = await _service.fetchSchedules(widget.barangayId);
    final remarksController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    DateTime selectedDate = DateTime.now();
    String selectedStatus = _collectionLogStatuses.first;
    int? selectedScheduleId;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create collection log',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Collection date'),
                        subtitle: Text(_formatDate(selectedDate)),
                        trailing: const Icon(Icons.calendar_today_outlined),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setModalState(() {
                              selectedDate = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                                selectedDate.hour,
                                selectedDate.minute,
                              );
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int?>(
                        initialValue: selectedScheduleId,
                        decoration: const InputDecoration(
                          labelText: 'Schedule (optional)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('No schedule'),
                          ),
                          ...schedules.map(
                            (schedule) => DropdownMenuItem<int?>(
                              value: schedule.id,
                              child: Text(
                                '${schedule.dayOfWeek} • ${schedule.wasteType.isEmpty ? 'Waste type not set' : schedule.wasteType}',
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setModalState(() {
                            selectedScheduleId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedStatus,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                        ),
                        items: _collectionLogStatuses
                            .map(
                              (status) => DropdownMenuItem<String>(
                                value: status,
                                child: Text(status),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setModalState(() {
                            selectedStatus = value;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: remarksController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Remarks',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                final form = formKey.currentState;
                                if (form == null || !form.validate()) {
                                  return;
                                }

                                try {
                                  await _service.createCollectionLog(
                                    barangayId: widget.barangayId,
                                    scheduleId: selectedScheduleId,
                                    collectionDate: selectedDate,
                                    status: selectedStatus,
                                    remarks: remarksController.text,
                                  );
                                  if (context.mounted) {
                                    Navigator.of(context).pop(true);
                                  }
                                } on PostgrestException catch (error) {
                                  if (!context.mounted) {
                                    return;
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        error.message.isNotEmpty
                                            ? error.message
                                            : 'Unable to create collection log.',
                                      ),
                                    ),
                                  );
                                } catch (error) {
                                  if (!context.mounted) {
                                    return;
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Unable to create collection log: $error',
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: const Text('Create'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    remarksController.dispose();

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Collection log created successfully.')),
      );
      await _refreshLogs();
      await _refreshCollectionPhotos();
    }
  }

  Future<void> _refreshCollectionPhotos() async {
    setState(() {
      _collectionPhotosFuture = _service.fetchCollectionPhotos(
        barangayId: widget.barangayId,
        limit: 8,
      );
    });
    await _collectionPhotosFuture;
  }

  String _normalizeResidentReportStatus(String value) {
    final normalized = value.trim().toLowerCase();
    if (_residentReportStatuses.contains(normalized)) {
      return normalized;
    }
    return 'pending';
  }

  Future<void> _updateResidentReportStatus(
    ResidentReportItem report,
    String status,
  ) async {
    if (_updatingReportIds.contains(report.id)) {
      return;
    }

    setState(() {
      _updatingReportIds.add(report.id);
    });

    try {
      await _service.updateResidentReportStatus(
        reportId: report.id,
        status: status,
      );
      if (!mounted) {
        return;
      }
      await _refreshReports();
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message.isNotEmpty
                ? error.message
                : 'Unable to update resident report status.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to update resident report status: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingReportIds.remove(report.id);
        });
      }
    }
  }

  void _subscribeToRealtimeChanges() {
    final schedulesChannel =
        Supabase.instance.client.channel(
            'details-schedules-${widget.barangayId}',
          )
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: AdminDashboardService.collectionSchedulesTable,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'barangay_id',
              value: '${widget.barangayId}',
            ),
            callback: (_) => _scheduleRealtimeRefresh(),
          )
          ..subscribe();

    final logsChannel =
        Supabase.instance.client.channel('details-logs-${widget.barangayId}')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: AdminDashboardService.collectionLogsTable,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'barangay_id',
              value: '${widget.barangayId}',
            ),
            callback: (_) => _scheduleRealtimeRefresh(),
          )
          ..subscribe();

    final reportsChannel =
        Supabase.instance.client.channel('details-reports-${widget.barangayId}')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: AdminDashboardService.wasteReportsTable,
            callback: (_) => _scheduleRealtimeRefresh(),
          )
          ..subscribe();

    final usersChannel =
        Supabase.instance.client.channel('details-users-${widget.barangayId}')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: AdminDashboardService.usersTable,
            callback: (_) => _scheduleRealtimeRefresh(),
          )
          ..subscribe();

    final photoStorageChannels = AdminDashboardService.collectionPhotoBuckets
        .toSet()
        .map((bucketId) {
          return Supabase.instance.client.channel(
              'details-storage-$bucketId-${widget.barangayId}',
            )
            ..onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'storage',
              table: 'objects',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'bucket_id',
                value: bucketId,
              ),
              callback: (_) => _scheduleRealtimeRefresh(),
            )
            ..subscribe();
        });

    _realtimeChannels
      ..add(schedulesChannel)
      ..add(logsChannel)
      ..add(reportsChannel)
      ..add(usersChannel)
      ..addAll(photoStorageChannels);
  }

  void _scheduleRealtimeRefresh() {
    if (!mounted) {
      return;
    }

    _realtimeRefreshDebounce?.cancel();
    _realtimeRefreshDebounce = Timer(_realtimeRefreshDebounceDuration, () {
      if (!mounted) {
        return;
      }

      setState(_reloadData);
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScrollChanged)
      ..dispose();
    _realtimeRefreshDebounce?.cancel();
    for (final channel in _realtimeChannels) {
      Supabase.instance.client.removeChannel(channel);
    }
    _realtimeChannels.clear();
    _logsSearchController.dispose();
    _reportsSearchController.dispose();
    _schedulesSearchController.dispose();
    super.dispose();
  }

  void _onScrollChanged() {
    final shouldShow =
        _scrollController.hasClients &&
        _scrollController.offset > _backToTopOffset;
    if (shouldShow != _showBackToTop) {
      setState(() {
        _showBackToTop = shouldShow;
      });
    }
  }

  void _handleBackNavigation() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    navigator.pushNamedAndRemoveUntil('/dashboard', (route) => false);
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) {
      return;
    }
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  List<T> _visibleItems<T>(List<T> items, {required bool showAll}) {
    if (showAll) {
      return items;
    }
    return items.take(_initialVisibleCount).toList();
  }

  bool _matchesQuery({required String query, required List<String> values}) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }

    return values.any((value) => value.toLowerCase().contains(normalizedQuery));
  }

  int _residentReportStatusPriority(String status) {
    final normalized = _normalizeResidentReportStatus(status);
    switch (normalized) {
      case 'pending':
        return 0;
      case 'in_review':
        return 1;
      case 'resolved':
        return 2;
      default:
        return 3;
    }
  }

  Future<void> _addSchedule() async {
    await _openScheduleForm();
  }

  Future<void> _editSchedule(CollectionScheduleItem schedule) async {
    await _openScheduleForm(schedule: schedule);
  }

  Future<void> _deleteSchedule(CollectionScheduleItem schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete schedule?'),
          content: Text(
            'This will permanently remove the ${schedule.dayOfWeek} schedule.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _service.deleteSchedule(scheduleId: schedule.id);
      if (!mounted) {
        return;
      }
      await _refreshSchedules();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Schedule deleted successfully.')),
      );
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message.isNotEmpty
                ? error.message
                : 'Unable to delete schedule.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to delete schedule: $error')),
      );
    }
  }

  Future<void> _openScheduleForm({CollectionScheduleItem? schedule}) async {
    final editingSchedule = schedule;
    final isEditing = editingSchedule != null;
    String? selectedDayOfWeek = editingSchedule?.dayOfWeek;
    if (selectedDayOfWeek != null &&
        !_dayOfWeekOptions.contains(selectedDayOfWeek)) {
      selectedDayOfWeek = null;
    }
    final selectedWasteTypes = <String>{};
    final existingWasteTypes = (editingSchedule?.wasteType ?? '')
        .split(',')
        .map((type) => type.trim())
        .where((type) => type.isNotEmpty);
    for (final existingType in existingWasteTypes) {
      for (final option in _wasteTypeOptions) {
        if (option.toLowerCase() == existingType.toLowerCase()) {
          selectedWasteTypes.add(option);
        }
      }
    }
    final notesController = TextEditingController(
      text: editingSchedule?.notes ?? '',
    );
    TimeOfDay? startTime = editingSchedule?.startTime;
    TimeOfDay? endTime = editingSchedule?.endTime;
    bool isActive = editingSchedule?.isActive ?? true;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEditing ? 'Update schedule' : 'Create schedule',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedDayOfWeek,
                      decoration: const InputDecoration(
                        labelText: 'Day of week',
                      ),
                      items: _dayOfWeekOptions
                          .map(
                            (day) => DropdownMenuItem<String>(
                              value: day,
                              child: Text(day),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setSheetState(() {
                          selectedDayOfWeek = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime:
                                    startTime ??
                                    const TimeOfDay(hour: 8, minute: 0),
                              );
                              if (picked != null) {
                                setSheetState(() {
                                  startTime = picked;
                                });
                              }
                            },
                            icon: const Icon(Icons.schedule_outlined),
                            label: Text(
                              startTime == null
                                  ? 'Set start time'
                                  : 'Start: ${_formatTimeOfDay(startTime!)}',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime:
                                    endTime ??
                                    const TimeOfDay(hour: 10, minute: 0),
                              );
                              if (picked != null) {
                                setSheetState(() {
                                  endTime = picked;
                                });
                              }
                            },
                            icon: const Icon(Icons.schedule_send_outlined),
                            label: Text(
                              endTime == null
                                  ? 'Set end time'
                                  : 'End: ${_formatTimeOfDay(endTime!)}',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Waste type',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._wasteTypeOptions.map(
                      (type) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(type),
                        value: selectedWasteTypes.contains(type),
                        onChanged: (checked) {
                          setSheetState(() {
                            if (checked == true) {
                              selectedWasteTypes.add(type);
                            } else {
                              selectedWasteTypes.remove(type);
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(labelText: 'Notes'),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active schedule'),
                      subtitle: const Text(
                        'Toggle whether this schedule is active.',
                      ),
                      value: isActive,
                      onChanged: (value) {
                        setSheetState(() {
                          isActive = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final dayOfWeek = (selectedDayOfWeek ?? '')
                                  .trim();
                              final wasteType = selectedWasteTypes.join(', ');

                              if (dayOfWeek.isEmpty || wasteType.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Day of week and waste type are required.',
                                    ),
                                  ),
                                );
                                return;
                              }

                              if (startTime == null || endTime == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Please select both start and end times.',
                                    ),
                                  ),
                                );
                                return;
                              }

                              try {
                                if (isEditing) {
                                  final onlyStatusChanged =
                                      dayOfWeek == editingSchedule.dayOfWeek &&
                                      wasteType == editingSchedule.wasteType &&
                                      notesController.text.trim() ==
                                          editingSchedule.notes.trim() &&
                                      startTime == editingSchedule.startTime &&
                                      endTime == editingSchedule.endTime &&
                                      isActive != editingSchedule.isActive;

                                  if (onlyStatusChanged) {
                                    await _service.updateScheduleStatus(
                                      scheduleId: editingSchedule.id,
                                      isActive: isActive,
                                    );
                                  } else {
                                    await _service.updateSchedule(
                                      schedule: editingSchedule,
                                      dayOfWeek: dayOfWeek,
                                      startTime: startTime!,
                                      endTime: endTime!,
                                      wasteType: wasteType,
                                      notes: notesController.text,
                                      isActive: isActive,
                                    );
                                  }
                                } else {
                                  await _service.createSchedule(
                                    barangayId: widget.barangayId,
                                    dayOfWeek: dayOfWeek,
                                    startTime: startTime!,
                                    endTime: endTime!,
                                    wasteType: wasteType,
                                    notes: notesController.text,
                                    isActive: isActive,
                                  );
                                }
                                if (context.mounted) {
                                  Navigator.of(context).pop(true);
                                }
                              } on PostgrestException catch (error) {
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      error.message.isNotEmpty
                                          ? error.message
                                          : 'Unable to save schedule.',
                                    ),
                                  ),
                                );
                              } catch (error) {
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Unable to save schedule: $error',
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Text(isEditing ? 'Save' : 'Create'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    notesController.dispose();

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            schedule == null
                ? 'Schedule created successfully.'
                : 'Schedule updated successfully.',
          ),
        ),
      );
      await _refreshSchedules();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to dashboard',
          onPressed: _handleBackNavigation,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(widget.barangayName),
      ),
      floatingActionButton: _showBackToTop
          ? FloatingActionButton.extended(
              onPressed: _scrollToTop,
              icon: const Icon(Icons.keyboard_arrow_up),
              label: const Text('Back to top'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _HeaderCard(
              barangayName: widget.barangayName,
              district: widget.district,
              city: widget.city,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Collection completion and compliance',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _openCollectionLogForm,
                  icon: const Icon(Icons.add),
                  label: const Text('Add log'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<CollectionLogItem>>(
              future: _logsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _SectionLoading();
                }
                if (snapshot.hasError) {
                  return _SectionError(
                    title: 'Collection logs unavailable',
                    message: snapshot.error.toString(),
                  );
                }

                final logs = snapshot.data ?? const <CollectionLogItem>[];
                final summary = _buildSummary(logs);
                final logStatusOptions =
                    logs
                        .map((log) => log.status.trim())
                        .where((status) => status.isNotEmpty)
                        .toSet()
                        .toList()
                      ..sort(
                        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                      );
                final logFilterOptions = <String>['All', ...logStatusOptions];
                final selectedLogFilter = logFilterOptions.contains(_logsFilter)
                    ? _logsFilter
                    : 'All';
                final filteredLogs = logs.where((log) {
                  final matchesQuery = _matchesQuery(
                    query: _logsQuery,
                    values: [
                      log.scheduleDayOfWeek,
                      log.scheduleWasteType,
                      log.remarks,
                      log.status,
                      log.barangayName,
                    ],
                  );
                  final matchesFilter =
                      selectedLogFilter == 'All' ||
                      log.status == selectedLogFilter;
                  return matchesQuery && matchesFilter;
                }).toList();
                final visibleLogs = _visibleItems(
                  filteredLogs,
                  showAll: _showAllLogs,
                );

                return Column(
                  children: [
                    _CompletionSummaryCard(summary: summary),
                    const SizedBox(height: 12),
                    _SearchAndFilterBar(
                      searchHint:
                          'Search logs by day, type, remarks, or status',
                      searchController: _logsSearchController,
                      filterLabel: 'Status',
                      filterValue: selectedLogFilter,
                      filterOptions: logFilterOptions,
                      onSearchChanged: (value) {
                        setState(() {
                          _logsQuery = value;
                          _showAllLogs = false;
                        });
                      },
                      onFilterChanged: (value) {
                        setState(() {
                          _logsFilter = value;
                          _showAllLogs = false;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    if (logs.isEmpty)
                      const _EmptyInlineState(
                        icon: Icons.inbox_outlined,
                        title: 'No collection logs found',
                        message:
                            'This barangay does not have collection logs yet.',
                      )
                    else if (filteredLogs.isEmpty)
                      const _EmptyInlineState(
                        icon: Icons.search_off,
                        title: 'No matching logs',
                        message:
                            'Try a different search keyword or status filter.',
                      )
                    else
                      ...visibleLogs.map(
                        (log) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _CollectionLogCard(
                            log: log,
                            selectedStatus: _normalizeCollectionLogStatus(
                              log.status,
                            ),
                            onStatusChanged: (value) =>
                                _updateCollectionLogStatus(log, value),
                          ),
                        ),
                      ),
                    if (filteredLogs.length > _initialVisibleCount)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _showAllLogs = !_showAllLogs;
                            });
                          },
                          icon: Icon(
                            _showAllLogs
                                ? Icons.expand_less
                                : Icons.expand_more,
                          ),
                          label: Text(_showAllLogs ? 'See less' : 'See more'),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Resident reports',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<ResidentReportItem>>(
              future: _reportsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _SectionLoading();
                }
                if (snapshot.hasError) {
                  return _SectionError(
                    title: 'Resident reports unavailable',
                    message: snapshot.error.toString(),
                  );
                }

                final reports = snapshot.data ?? const <ResidentReportItem>[];
                final reportStatusOptions =
                    reports
                        .map((report) => report.status.trim())
                        .where((status) => status.isNotEmpty)
                        .toSet()
                        .toList()
                      ..sort(
                        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                      );
                final reportFilterOptions = <String>[
                  'All',
                  ...reportStatusOptions,
                ];
                final selectedReportFilter =
                    reportFilterOptions.contains(_reportsFilter)
                    ? _reportsFilter
                    : 'All';
                final filteredReports =
                    reports.where((report) {
                      final matchesQuery = _matchesQuery(
                        query: _reportsQuery,
                        values: [
                          report.residentName,
                          report.address,
                          report.addressText,
                          report.description,
                          report.status,
                        ],
                      );
                      final matchesFilter =
                          selectedReportFilter == 'All' ||
                          report.status == selectedReportFilter;
                      return matchesQuery && matchesFilter;
                    }).toList()..sort((a, b) {
                      final priorityCompare = _residentReportStatusPriority(
                        a.status,
                      ).compareTo(_residentReportStatusPriority(b.status));
                      if (priorityCompare != 0) {
                        return priorityCompare;
                      }

                      final aDate = a.createdAt;
                      final bDate = b.createdAt;
                      if (aDate == null && bDate == null) {
                        return 0;
                      }
                      if (aDate == null) {
                        return 1;
                      }
                      if (bDate == null) {
                        return -1;
                      }
                      return bDate.compareTo(aDate);
                    });
                final visibleReports = _visibleItems(
                  filteredReports,
                  showAll: _showAllReports,
                );

                return Column(
                  children: [
                    _SearchAndFilterBar(
                      searchHint:
                          'Search reports by resident, address, or status',
                      searchController: _reportsSearchController,
                      filterLabel: 'Status',
                      filterValue: selectedReportFilter,
                      filterOptions: reportFilterOptions,
                      onSearchChanged: (value) {
                        setState(() {
                          _reportsQuery = value;
                          _showAllReports = false;
                        });
                      },
                      onFilterChanged: (value) {
                        setState(() {
                          _reportsFilter = value;
                          _showAllReports = false;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    if (reports.isEmpty)
                      const _EmptyInlineState(
                        icon: Icons.report_outlined,
                        title: 'No resident reports found',
                        message:
                            'Resident reports linked to this barangay will appear here.',
                      )
                    else if (filteredReports.isEmpty)
                      const _EmptyInlineState(
                        icon: Icons.search_off,
                        title: 'No matching reports',
                        message:
                            'Try a different search keyword or status filter.',
                      )
                    else
                      ...visibleReports.map(
                        (report) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ResidentReportCard(
                            report: report,
                            selectedStatus: _normalizeResidentReportStatus(
                              report.status,
                            ),
                            isUpdating: _updatingReportIds.contains(report.id),
                            onStatusChanged: (value) =>
                                _updateResidentReportStatus(report, value),
                          ),
                        ),
                      ),
                    if (filteredReports.length > _initialVisibleCount)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _showAllReports = !_showAllReports;
                            });
                          },
                          icon: Icon(
                            _showAllReports
                                ? Icons.expand_less
                                : Icons.expand_more,
                          ),
                          label: Text(
                            _showAllReports ? 'See less' : 'See more',
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Collection photos',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh photos',
                  onPressed: _refreshCollectionPhotos,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<String>>(
              future: _collectionPhotosFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _SectionLoading();
                }
                if (snapshot.hasError) {
                  return _SectionError(
                    title: 'Collection photos unavailable',
                    message: snapshot.error.toString(),
                  );
                }

                final photos = snapshot.data ?? const <String>[];
                if (photos.isEmpty) {
                  return const _EmptyInlineState(
                    icon: Icons.photo_library_outlined,
                    title: 'No collection photos found',
                    message:
                        'This barangay does not have collection photos yet.',
                  );
                }

                return _PhotoCarousel(photoUrls: photos);
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Schedules',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _addSchedule,
                icon: const Icon(Icons.add),
                label: const Text('Add schedule'),
              ),
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<CollectionScheduleItem>>(
              future: _schedulesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _SectionLoading();
                }
                if (snapshot.hasError) {
                  return _SectionError(
                    title: 'Schedules unavailable',
                    message: snapshot.error.toString(),
                  );
                }

                final schedules =
                    snapshot.data ?? const <CollectionScheduleItem>[];
                const scheduleFilterOptions = <String>[
                  'All',
                  'Active',
                  'Inactive',
                ];
                final selectedScheduleFilter =
                    scheduleFilterOptions.contains(_schedulesFilter)
                    ? _schedulesFilter
                    : 'All';
                final filteredSchedules = schedules.where((schedule) {
                  final matchesQuery = _matchesQuery(
                    query: _schedulesQuery,
                    values: [
                      schedule.dayOfWeek,
                      schedule.wasteType,
                      schedule.notes,
                      schedule.barangayName,
                      schedule.city,
                    ],
                  );
                  final matchesFilter =
                      selectedScheduleFilter == 'All' ||
                      (selectedScheduleFilter == 'Active' &&
                          schedule.isActive) ||
                      (selectedScheduleFilter == 'Inactive' &&
                          !schedule.isActive);
                  return matchesQuery && matchesFilter;
                }).toList();
                final visibleSchedules = _visibleItems(
                  filteredSchedules,
                  showAll: _showAllSchedules,
                );

                return Column(
                  children: [
                    _SearchAndFilterBar(
                      searchHint:
                          'Search schedules by day, waste type, notes, or city',
                      searchController: _schedulesSearchController,
                      filterLabel: 'Status',
                      filterValue: selectedScheduleFilter,
                      filterOptions: scheduleFilterOptions,
                      onSearchChanged: (value) {
                        setState(() {
                          _schedulesQuery = value;
                          _showAllSchedules = false;
                        });
                      },
                      onFilterChanged: (value) {
                        setState(() {
                          _schedulesFilter = value;
                          _showAllSchedules = false;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    if (schedules.isEmpty)
                      const _EmptyInlineState(
                        icon: Icons.calendar_month_outlined,
                        title: 'No schedules found',
                        message:
                            'Create collection schedules for this barangay in Supabase.',
                      )
                    else if (filteredSchedules.isEmpty)
                      const _EmptyInlineState(
                        icon: Icons.search_off,
                        title: 'No matching schedules',
                        message:
                            'Try a different search keyword or status filter.',
                      )
                    else
                      ...visibleSchedules.map(
                        (schedule) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ScheduleCard(
                            schedule: schedule,
                            onEditPressed: () => _editSchedule(schedule),
                            onDeletePressed: () => _deleteSchedule(schedule),
                          ),
                        ),
                      ),
                    if (filteredSchedules.length > _initialVisibleCount)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _showAllSchedules = !_showAllSchedules;
                            });
                          },
                          icon: Icon(
                            _showAllSchedules
                                ? Icons.expand_less
                                : Icons.expand_more,
                          ),
                          label: Text(
                            _showAllSchedules ? 'See less' : 'See more',
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  _CompletionSummary _buildSummary(List<CollectionLogItem> logs) {
    final completedLogs = logs.where((log) => log.isCompleted).length;
    final pendingLogs = logs.length - completedLogs;
    final complianceRate = logs.isEmpty
        ? 0.0
        : (completedLogs / logs.length) * 100;
    final latestLog = logs.isEmpty ? null : logs.first;

    return _CompletionSummary(
      totalLogs: logs.length,
      completedLogs: completedLogs,
      pendingLogs: pendingLogs,
      complianceRate: complianceRate,
      latestStatus: latestLog?.status ?? 'No logs yet',
      latestDate: latestLog?.referenceDate,
    );
  }

  String _normalizeCollectionLogStatus(String value) {
    final normalized = value.trim().toLowerCase();
    if (_collectionLogStatuses.contains(normalized)) {
      return normalized;
    }
    return 'pending';
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.barangayName,
    required this.district,
    required this.city,
  });

  final String barangayName;
  final String district;
  final String city;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.secondary, scheme.tertiary],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.location_on_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  barangayName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            [
              district,
              city,
            ].where((text) => text.trim().isNotEmpty).join(' • '),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Review collection performance, resident reports, and active schedules for this barangay.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletionSummaryCard extends StatelessWidget {
  const _CompletionSummaryCard({required this.summary});

  final _CompletionSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${summary.complianceRate.toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Completion rate',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      summary.latestStatus,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: summary.complianceRate.clamp(0, 100) / 100,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Completed',
                  value: '${summary.completedLogs}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  label: 'Pending',
                  value: '${summary.pendingLogs}',
                ),
              ),
              const SizedBox(width: 19),
              Expanded(
                child: _MetricTile(
                  label: 'Total logs',
                  value: '${summary.totalLogs}',
                ),
              ),
            ],
          ),
          if (summary.latestDate != null) ...[
            const SizedBox(height: 12),
            Text(
              'Latest log: ${_formatDate(summary.latestDate!)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CollectionLogCard extends StatelessWidget {
  const _CollectionLogCard({
    required this.log,
    required this.selectedStatus,
    required this.onStatusChanged,
  });

  final CollectionLogItem log;
  final String selectedStatus;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${log.scheduleDayOfWeek.isEmpty ? 'Collection log' : log.scheduleDayOfWeek} • ${_formatDate(log.collectionDate)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${log.scheduleWasteType.isEmpty ? 'Waste type not specified' : log.scheduleWasteType} • ${log.barangayName}',
                ),
                const SizedBox(height: 10),
                Text(
                  log.remarks.isEmpty ? 'No remarks provided.' : log.remarks,
                ),
                const SizedBox(height: 8),
                Text(
                  'Time: ${_formatTimeOfDay(log.scheduleStartTime)} - ${_formatTimeOfDay(log.scheduleEndTime)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: DropdownButtonFormField<String>(
              initialValue: selectedStatus,
              isDense: true,
              iconSize: 18,
              style: Theme.of(context).textTheme.labelSmall,
              decoration: const InputDecoration(
                labelText: 'Status',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
                DropdownMenuItem(value: 'missed', child: Text('Missed')),
              ],
              onChanged: (value) {
                if (value == null || value == selectedStatus) {
                  return;
                }
                onStatusChanged(value);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ResidentReportCard extends StatefulWidget {
  const _ResidentReportCard({
    required this.report,
    required this.selectedStatus,
    required this.onStatusChanged,
    required this.isUpdating,
  });

  final ResidentReportItem report;
  final String selectedStatus;
  final ValueChanged<String> onStatusChanged;
  final bool isUpdating;

  @override
  State<_ResidentReportCard> createState() => _ResidentReportCardState();
}

class _ResidentReportCardState extends State<_ResidentReportCard> {
  final AdminDashboardService _service = AdminDashboardService();
  late Future<String?> _photoUrlFuture;

  @override
  void initState() {
    super.initState();
    _photoUrlFuture = _service.resolveReportPhotoUrl(widget.report);
  }

  @override
  void didUpdateWidget(covariant _ResidentReportCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report.id != widget.report.id) {
      _photoUrlFuture = _service.resolveReportPhotoUrl(widget.report);
    }
  }

  Future<void> _openPhotoViewer(String imageUrl) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Unable to load photo.'),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    label: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.report.residentName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 130,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: widget.selectedStatus,
                      isDense: true,
                      iconSize: 18,
                      style: Theme.of(context).textTheme.labelSmall,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'pending',
                          child: Text('Pending'),
                        ),
                        DropdownMenuItem(
                          value: 'in_review',
                          child: Text('In review'),
                        ),
                        DropdownMenuItem(
                          value: 'resolved',
                          child: Text('Resolved'),
                        ),
                      ],
                      onChanged: widget.isUpdating
                          ? null
                          : (value) {
                              if (value == null ||
                                  value == widget.selectedStatus) {
                                return;
                              }
                              widget.onStatusChanged(value);
                            },
                    ),
                    if (widget.isUpdating) ...[
                      const SizedBox(height: 8),
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.report.addressText.isEmpty
                ? widget.report.address
                : widget.report.addressText,
          ),
          const SizedBox(height: 8),
          Text(
            widget.report.description.isEmpty
                ? 'No description provided.'
                : widget.report.description,
          ),
          const SizedBox(height: 10),
          Text(
            'Contact: ${widget.report.phone.isEmpty ? 'No phone' : widget.report.phone} • ${widget.report.email.isEmpty ? 'No email' : widget.report.email}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (widget.report.reviewNotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Review notes: ${widget.report.reviewNotes}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (widget.report.hasPhoto) ...[
            const SizedBox(height: 12),
            FutureBuilder<String?>(
              future: _photoUrlFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Center(child: CircularProgressIndicator()),
                  );
                }

                final imageUrl = snapshot.data;
                if (imageUrl == null || imageUrl.isEmpty) {
                  return Container(
                    height: 180,
                    width: double.infinity,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.35,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text('Photo not available in storage yet.'),
                  );
                }

                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _openPhotoViewer(imageUrl),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        children: [
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: scheme.surfaceContainerHighest
                                      .withValues(alpha: 0.35),
                                  alignment: Alignment.center,
                                  child: const Text('Unable to load photo.'),
                                );
                              },
                            ),
                          ),
                          Positioned(
                            right: 12,
                            top: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'View photo',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.schedule,
    required this.onEditPressed,
    required this.onDeletePressed,
  });

  final CollectionScheduleItem schedule;
  final VoidCallback onEditPressed;
  final VoidCallback onDeletePressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  schedule.dayOfWeek,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StatusChip(label: schedule.isActive ? 'Active' : 'Inactive'),
            ],
          ),
          const SizedBox(height: 8),
          Text('${schedule.barangayName} • ${schedule.city}'),
          const SizedBox(height: 8),
          Text(
            '${schedule.wasteType.isEmpty ? 'Waste type not set' : schedule.wasteType} | ${_formatTimeOfDay(schedule.startTime)} - ${_formatTimeOfDay(schedule.endTime)}',
          ),
          const SizedBox(height: 8),
          Text(schedule.notes.isEmpty ? 'No notes provided.' : schedule.notes),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.tonalIcon(
                onPressed: onEditPressed,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Update'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onDeletePressed,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoCarousel extends StatefulWidget {
  const _PhotoCarousel({required this.photoUrls});

  final List<String> photoUrls;

  @override
  State<_PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<_PhotoCarousel> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.82);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          height: 170,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.photoUrls.length,
            onPageChanged: (value) {
              setState(() {
                _currentIndex = value;
              });
            },
            itemBuilder: (context, index) {
              final imageUrl = widget.photoUrls[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Text(
                            'Unable to load image',
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.photoUrls.length,
            (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: _currentIndex == index ? 16 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: _currentIndex == index
                    ? scheme.primary
                    : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchAndFilterBar extends StatelessWidget {
  const _SearchAndFilterBar({
    required this.searchHint,
    required this.searchController,
    required this.filterLabel,
    required this.filterValue,
    required this.filterOptions,
    required this.onSearchChanged,
    required this.onFilterChanged,
  });

  final String searchHint;
  final TextEditingController searchController;
  final String filterLabel;
  final String filterValue;
  final List<String> filterOptions;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final searchField = TextField(
      controller: searchController,
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        hintText: searchHint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: () {
                  searchController.clear();
                  onSearchChanged('');
                },
              ),
        border: const OutlineInputBorder(),
      ),
    );

    final filterField = DropdownButtonFormField<String>(
      initialValue: filterValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: filterLabel,
        prefixIcon: const Icon(Icons.filter_list),
        border: const OutlineInputBorder(),
      ),
      items: filterOptions
          .map(
            (option) =>
                DropdownMenuItem<String>(value: option, child: Text(option)),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          onFilterChanged(value);
        }
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 720;
        if (isNarrow) {
          return Column(
            children: [searchField, const SizedBox(height: 10), filterField],
          );
        }

        return Row(
          children: [
            Expanded(flex: 3, child: searchField),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: filterField),
          ],
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final normalized = label.toLowerCase();
    final backgroundColor =
        normalized.contains('active') || normalized.contains('complete')
        ? Colors.green.withValues(alpha: 0.15)
        : normalized.contains('pending') || normalized.contains('inactive')
        ? Colors.orange.withValues(alpha: 0.15)
        : Colors.blue.withValues(alpha: 0.15);
    final foregroundColor =
        normalized.contains('active') || normalized.contains('complete')
        ? Colors.green.shade800
        : normalized.contains('pending') || normalized.contains('inactive')
        ? Colors.orange.shade800
        : Colors.blue.shade800;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(24),
      ),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(message),
        ],
      ),
    );
  }
}

class _EmptyInlineState extends StatelessWidget {
  const _EmptyInlineState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 38, color: scheme.primary),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CompletionSummary {
  const _CompletionSummary({
    required this.totalLogs,
    required this.completedLogs,
    required this.pendingLogs,
    required this.complianceRate,
    required this.latestStatus,
    required this.latestDate,
  });

  final int totalLogs;
  final int completedLogs;
  final int pendingLogs;
  final double complianceRate;
  final String latestStatus;
  final DateTime? latestDate;
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final year = local.year;
  return '$day/$month/$year';
}

String _formatTimeOfDay(TimeOfDay? value) {
  if (value == null) {
    return '--:--';
  }

  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
