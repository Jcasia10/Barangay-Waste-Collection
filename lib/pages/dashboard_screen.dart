import 'package:exam/services/admin_dashboard_service.dart';
import 'package:flutter/material.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({required this.onLogout, super.key});

  final VoidCallback onLogout;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AdminDashboardService _service = AdminDashboardService();
  static const int _initialVisibleCount = 3;
  static const double _backToTopOffset = 320;

  late Future<List<BarangaySummary>> _barangayFuture;
  late Future<List<CollectionLogItem>> _recentLogsFuture;
  late Future<List<CollectionScheduleItem>> _activeSchedulesFuture;
  late Future<List<ResidentReportItem>> _recentReportsFuture;

  String _barangayQuery = '';
  String _barangayFilter = 'All';
  bool _showAllBarangays = false;
  final TextEditingController _barangaySearchController =
      TextEditingController();

  String _logsQuery = '';
  String _logsFilter = 'All';
  bool _showAllLogs = false;
  final TextEditingController _logsSearchController = TextEditingController();

  String _scheduleQuery = '';
  String _scheduleFilter = 'All';
  bool _showAllSchedules = false;
  final TextEditingController _scheduleSearchController =
      TextEditingController();

  String _reportQuery = '';
  String _reportFilter = 'All';
  bool _showAllReports = false;
  final TextEditingController _reportSearchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _scrollController.addListener(_onScrollChanged);
  }

  void _loadDashboardData() {
    _barangayFuture = _service.fetchBarangaySummaries();
    _recentLogsFuture = _service.fetchRecentCollectionLogs(limit: 100);
    _activeSchedulesFuture = _service.fetchActiveSchedules(limit: 100);
    _recentReportsFuture = _service.fetchRecentReports(limit: 100);
  }

  Future<void> _reload() async {
    setState(() {
      _loadDashboardData();
    });
    await Future.wait([
      _barangayFuture,
      _recentLogsFuture,
      _activeSchedulesFuture,
      _recentReportsFuture,
    ]);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScrollChanged)
      ..dispose();
    _barangaySearchController.dispose();
    _logsSearchController.dispose();
    _scheduleSearchController.dispose();
    _reportSearchController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Waste Collection Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: _DashboardMenu(onLogout: widget.onLogout),
      floatingActionButton: _showBackToTop
          ? FloatingActionButton.extended(
              onPressed: _scrollToTop,
              icon: const Icon(Icons.keyboard_arrow_up),
              label: const Text('Back to top'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<BarangaySummary>>(
          future: _barangayFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _DashboardLoading();
            }

            if (snapshot.hasError) {
              return _DashboardError(
                message: snapshot.error.toString(),
                onRetry: _reload,
              );
            }

            final barangays = snapshot.data ?? const <BarangaySummary>[];
            final totalLogs = barangays.fold<int>(
              0,
              (sum, barangay) => sum + barangay.totalLogs,
            );
            final completedLogs = barangays.fold<int>(
              0,
              (sum, barangay) => sum + barangay.completedLogs,
            );
            final averageCompliance = barangays.isEmpty
                ? 0.0
                : barangays.fold<double>(
                        0,
                        (sum, barangay) => sum + barangay.complianceRate,
                      ) /
                      barangays.length;
            final barangayById = {
              for (final barangay in barangays) barangay.id: barangay,
            };
            final districtOptions =
                barangays
                    .map((barangay) => barangay.district.trim())
                    .where((district) => district.isNotEmpty)
                    .toSet()
                    .toList()
                  ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
            final barangayFilterOptions = <String>['All', ...districtOptions];
            final selectedBarangayFilter =
                barangayFilterOptions.contains(_barangayFilter)
                ? _barangayFilter
                : 'All';
            final filteredBarangays = barangays.where((barangay) {
              final matchesQuery = _matchesQuery(
                query: _barangayQuery,
                values: [
                  barangay.name,
                  barangay.city,
                  barangay.district,
                  barangay.latestStatus,
                ],
              );
              final matchesFilter =
                  selectedBarangayFilter == 'All' ||
                  barangay.district == selectedBarangayFilter;
              return matchesQuery && matchesFilter;
            }).toList();
            final visibleBarangays = _visibleItems(
              filteredBarangays,
              showAll: _showAllBarangays,
            );

            return ListView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                _HeroPanel(
                  totalBarangays: barangays.length,
                  totalLogs: totalLogs,
                  completedLogs: completedLogs,
                  averageCompliance: averageCompliance,
                ),
                const SizedBox(height: 16),
                Text(
                  'Collection Completion by Barangay',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _SearchAndFilterBar(
                  searchHint: 'Search barangay, city, district, or status',
                  searchController: _barangaySearchController,
                  filterLabel: 'District',
                  filterValue: selectedBarangayFilter,
                  filterOptions: barangayFilterOptions,
                  onSearchChanged: (value) {
                    setState(() {
                      _barangayQuery = value;
                      _showAllBarangays = false;
                    });
                  },
                  onFilterChanged: (value) {
                    setState(() {
                      _barangayFilter = value;
                      _showAllBarangays = false;
                    });
                  },
                ),
                const SizedBox(height: 10),
                if (barangays.isEmpty)
                  const _EmptyState(
                    icon: Icons.maps_home_work_outlined,
                    title: 'No collection logs yet',
                    message:
                        'Once Supabase starts returning collection logs, each barangay will appear here with a details button.',
                  )
                else if (filteredBarangays.isEmpty)
                  const _EmptyState(
                    icon: Icons.search_off,
                    title: 'No matching barangay',
                    message:
                        'Try a different keyword or district filter to find the barangay.',
                  )
                else
                  ...visibleBarangays.map(
                    (barangay) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _BarangayCompletionCard(
                        summary: barangay,
                        onDetailsPressed: () {
                          Navigator.of(context).pushNamed(
                            '/details',
                            arguments: {
                              'barangayId': barangay.id,
                              'barangayName': barangay.name,
                              'district': barangay.district,
                              'city': barangay.city,
                            },
                          );
                        },
                      ),
                    ),
                  ),
                if (filteredBarangays.length > _initialVisibleCount)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _showAllBarangays = !_showAllBarangays;
                        });
                      },
                      icon: Icon(
                        _showAllBarangays
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                      label: Text(_showAllBarangays ? 'See less' : 'See more'),
                    ),
                  ),
                const SizedBox(height: 16),
                _SectionHeader(
                  title: 'Recent collection logs',
                  subtitle: 'Latest activity from the collection tables',
                ),
                const SizedBox(height: 10),
                FutureBuilder<List<CollectionLogItem>>(
                  future: _recentLogsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const _DashboardSectionSkeleton(itemHeight: 112);
                    }
                    if (snapshot.hasError) {
                      return _EmptyState(
                        icon: Icons.error_outline,
                        title: 'Recent logs unavailable',
                        message: snapshot.error.toString(),
                      );
                    }

                    final logs = snapshot.data ?? const <CollectionLogItem>[];
                    final logStatusOptions =
                        logs
                            .map((log) => log.status.trim())
                            .where((status) => status.isNotEmpty)
                            .toSet()
                            .toList()
                          ..sort(
                            (a, b) =>
                                a.toLowerCase().compareTo(b.toLowerCase()),
                          );
                    final logFilterOptions = <String>[
                      'All',
                      ...logStatusOptions,
                    ];
                    final selectedLogFilter =
                        logFilterOptions.contains(_logsFilter)
                        ? _logsFilter
                        : 'All';
                    final filteredLogs = logs.where((log) {
                      final matchesQuery = _matchesQuery(
                        query: _logsQuery,
                        values: [
                          log.barangayName,
                          log.barangayDistrict,
                          log.barangayCity,
                          log.scheduleDayOfWeek,
                          log.remarks,
                          log.status,
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
                        _SearchAndFilterBar(
                          searchHint: 'Search by barangay, status, or remarks',
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
                          const _EmptyState(
                            icon: Icons.inbox_outlined,
                            title: 'No recent logs',
                            message:
                                'When collection logs are added in Supabase, they will appear here.',
                          )
                        else if (filteredLogs.isEmpty)
                          const _EmptyState(
                            icon: Icons.search_off,
                            title: 'No matching logs',
                            message:
                                'Try a different keyword or status filter to find logs.',
                          )
                        else
                          ...visibleLogs
                              .map(
                                (log) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _RecentLogCard(
                                    log: log,
                                    onTap: () {
                                      Navigator.of(context).pushNamed(
                                        '/details',
                                        arguments: {
                                          'barangayId': log.barangayId,
                                          'barangayName': log.barangayName,
                                          'district': log.barangayDistrict,
                                          'city': log.barangayCity,
                                        },
                                      );
                                    },
                                  ),
                                ),
                              )
                              .toList(),
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
                              label: Text(
                                _showAllLogs ? 'See less' : 'See more',
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                _SectionHeader(
                  title: 'Active schedules',
                  subtitle: 'Current pickup schedules across barangays',
                ),
                const SizedBox(height: 10),
                FutureBuilder<List<CollectionScheduleItem>>(
                  future: _activeSchedulesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const _DashboardSectionSkeleton(itemHeight: 104);
                    }
                    if (snapshot.hasError) {
                      return _EmptyState(
                        icon: Icons.error_outline,
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
                        scheduleFilterOptions.contains(_scheduleFilter)
                        ? _scheduleFilter
                        : 'All';
                    final filteredSchedules = schedules.where((schedule) {
                      final matchesQuery = _matchesQuery(
                        query: _scheduleQuery,
                        values: [
                          schedule.barangayName,
                          schedule.district,
                          schedule.city,
                          schedule.dayOfWeek,
                          schedule.wasteType,
                          schedule.notes,
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
                              'Search by barangay, day, waste type, or notes',
                          searchController: _scheduleSearchController,
                          filterLabel: 'Status',
                          filterValue: selectedScheduleFilter,
                          filterOptions: scheduleFilterOptions,
                          onSearchChanged: (value) {
                            setState(() {
                              _scheduleQuery = value;
                              _showAllSchedules = false;
                            });
                          },
                          onFilterChanged: (value) {
                            setState(() {
                              _scheduleFilter = value;
                              _showAllSchedules = false;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        if (schedules.isEmpty)
                          const _EmptyState(
                            icon: Icons.calendar_month_outlined,
                            title: 'No active schedules',
                            message:
                                'Create active schedules in the details screen to populate this area.',
                          )
                        else if (filteredSchedules.isEmpty)
                          const _EmptyState(
                            icon: Icons.search_off,
                            title: 'No matching schedules',
                            message:
                                'Try a different keyword or status filter to find schedules.',
                          )
                        else
                          ...visibleSchedules
                              .map(
                                (schedule) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _SchedulePreviewCard(
                                    schedule: schedule,
                                    onTap: () {
                                      Navigator.of(context).pushNamed(
                                        '/details',
                                        arguments: {
                                          'barangayId': schedule.barangayId,
                                          'barangayName': schedule.barangayName,
                                          'district': schedule.district,
                                          'city': schedule.city,
                                        },
                                      );
                                    },
                                  ),
                                ),
                              )
                              .toList(),
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
                const SizedBox(height: 16),
                _SectionHeader(
                  title: 'Recent resident reports',
                  subtitle: 'New reports waiting for admin review',
                ),
                const SizedBox(height: 10),
                FutureBuilder<List<ResidentReportItem>>(
                  future: _recentReportsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const _DashboardSectionSkeleton(itemHeight: 116);
                    }
                    if (snapshot.hasError) {
                      return _EmptyState(
                        icon: Icons.error_outline,
                        title: 'Reports unavailable',
                        message: snapshot.error.toString(),
                      );
                    }

                    final reports =
                        snapshot.data ?? const <ResidentReportItem>[];
                    final reportStatusOptions =
                        reports
                            .map((report) => report.status.trim())
                            .where((status) => status.isNotEmpty)
                            .toSet()
                            .toList()
                          ..sort(
                            (a, b) =>
                                a.toLowerCase().compareTo(b.toLowerCase()),
                          );
                    final reportFilterOptions = <String>[
                      'All',
                      ...reportStatusOptions,
                    ];
                    final selectedReportFilter =
                        reportFilterOptions.contains(_reportFilter)
                        ? _reportFilter
                        : 'All';
                    final filteredReports = reports.where((report) {
                      final matchesQuery = _matchesQuery(
                        query: _reportQuery,
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
                    }).toList();
                    final visibleReports = _visibleItems(
                      filteredReports,
                      showAll: _showAllReports,
                    );

                    return Column(
                      children: [
                        _SearchAndFilterBar(
                          searchHint:
                              'Search by resident, barangay address, or status',
                          searchController: _reportSearchController,
                          filterLabel: 'Status',
                          filterValue: selectedReportFilter,
                          filterOptions: reportFilterOptions,
                          onSearchChanged: (value) {
                            setState(() {
                              _reportQuery = value;
                              _showAllReports = false;
                            });
                          },
                          onFilterChanged: (value) {
                            setState(() {
                              _reportFilter = value;
                              _showAllReports = false;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        if (reports.isEmpty)
                          const _EmptyState(
                            icon: Icons.report_outlined,
                            title: 'No recent reports',
                            message:
                                'Resident reports synced from Supabase will show up here.',
                          )
                        else if (filteredReports.isEmpty)
                          const _EmptyState(
                            icon: Icons.search_off,
                            title: 'No matching reports',
                            message:
                                'Try a different keyword or status filter to find reports.',
                          )
                        else
                          ...visibleReports.map((report) {
                            final reportBarangay = report.userBarangayId == null
                                ? null
                                : barangayById[report.userBarangayId!];

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _ReportPreviewCard(
                                report: report,
                                barangayName:
                                    reportBarangay?.name ?? 'Unknown barangay',
                                onTap: reportBarangay == null
                                    ? null
                                    : () {
                                        Navigator.of(context).pushNamed(
                                          '/details',
                                          arguments: {
                                            'barangayId': reportBarangay.id,
                                            'barangayName': reportBarangay.name,
                                            'district': reportBarangay.district,
                                            'city': reportBarangay.city,
                                          },
                                        );
                                      },
                              ),
                            );
                          }).toList(),
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
              ],
            );
          },
        ),
      ),
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
      value: filterValue,
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

class _DashboardMenu extends StatelessWidget {
  const _DashboardMenu({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.secondary,
                ],
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.delete_outline, size: 38, color: Colors.white),
                SizedBox(height: 6),
                Text(
                  'Collection Menu',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            onTap: () {
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/settings');
            },
          ),
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('My Account'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/my-account');
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Log Out'),
            onTap: () {
              Navigator.of(context).pop();
              onLogout();
            },
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.isDarkMode,
    required this.onThemeChanged,
    required this.onLogout,
    super.key,
  });

  final bool isDarkMode;
  final Future<void> Function(bool) onThemeChanged;
  final VoidCallback onLogout;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _isDarkMode;

  @override
  void initState() {
    super.initState();
    _isDarkMode = widget.isDarkMode;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Dark Mode'),
            subtitle: const Text('Switch between light and dark theme.'),
            value: _isDarkMode,
            onChanged: (value) async {
              setState(() {
                _isDarkMode = value;
              });
              await widget.onThemeChanged(value);
            },
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
            label: const Text('Log Out'),
          ),
        ],
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.totalBarangays,
    required this.totalLogs,
    required this.completedLogs,
    required this.averageCompliance,
  });

  final int totalBarangays;
  final int totalLogs;
  final int completedLogs;
  final double averageCompliance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary, scheme.secondary],
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.recycling, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Admin command center',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Monitor collection completion, inspect barangay performance, and jump into each details screen for resident reports and schedule control.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _HeroStatChip(label: 'Barangays', value: '$totalBarangays'),
              _HeroStatChip(label: 'Logs', value: '$totalLogs'),
              _HeroStatChip(label: 'Completed', value: '$completedLogs'),
              _HeroStatChip(
                label: 'Avg. compliance',
                value: '${averageCompliance.toStringAsFixed(1)}%',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStatChip extends StatelessWidget {
  const _HeroStatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarangayCompletionCard extends StatelessWidget {
  const _BarangayCompletionCard({
    required this.summary,
    required this.onDetailsPressed,
  });

  final BarangaySummary summary;
  final VoidCallback onDetailsPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = summary.complianceRate.clamp(0, 100) / 100;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary.latestStatus,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${summary.complianceRate.toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: percent,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _CompactMetric(
                label: 'Completed',
                value: '${summary.completedLogs}',
              ),
              const SizedBox(width: 12),
              _CompactMetric(label: 'Pending', value: '${summary.pendingLogs}'),
              const SizedBox(width: 12),
              _CompactMetric(label: 'Reports', value: '${summary.reportCount}'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.access_time, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  summary.latestUpdate == null
                      ? 'No timestamp yet'
                      : 'Latest update: ${_formatDate(summary.latestUpdate!)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: onDetailsPressed,
                icon: const Icon(Icons.chevron_right),
                label: const Text('Details'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
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
      ),
    );
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: const [
        _SkeletonBlock(height: 220),
        SizedBox(height: 16),
        _SkeletonBlock(height: 130),
        SizedBox(height: 12),
        _SkeletonBlock(height: 130),
        SizedBox(height: 12),
        _SkeletonBlock(height: 130),
        SizedBox(height: 16),
        _SkeletonBlock(height: 120),
        SizedBox(height: 12),
        _SkeletonBlock(height: 120),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DashboardSectionSkeleton extends StatelessWidget {
  const _DashboardSectionSkeleton({required this.itemHeight});

  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        2,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SkeletonBlock(height: itemHeight),
        ),
      ),
    );
  }
}

class _RecentLogCard extends StatelessWidget {
  const _RecentLogCard({required this.log, required this.onTap});

  final CollectionLogItem log;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.local_shipping_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.barangayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${log.scheduleDayOfWeek.isEmpty ? 'Collection log' : log.scheduleDayOfWeek} • ${_formatDate(log.collectionDate)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      log.remarks.isEmpty ? 'No remarks provided' : log.remarks,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(label: log.status),
            ],
          ),
        ),
      ),
    );
  }
}

class _SchedulePreviewCard extends StatelessWidget {
  const _SchedulePreviewCard({required this.schedule, required this.onTap});

  final CollectionScheduleItem schedule;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.calendar_month_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${schedule.dayOfWeek} • ${schedule.barangayName}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${schedule.wasteType.isEmpty ? 'Waste type not set' : schedule.wasteType} • ${_formatTimeOfDay(schedule.startTime?.format(context) ?? 'N/A')} - ${_formatTimeOfDay(schedule.endTime?.format(context) ?? 'N/A')}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(label: schedule.isActive ? 'Active' : 'Inactive'),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportPreviewCard extends StatelessWidget {
  const _ReportPreviewCard({
    required this.report,
    required this.barangayName,
    this.onTap,
  });

  final ResidentReportItem report;
  final String barangayName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.report_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.residentName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Barangay: $barangayName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      report.addressText.isEmpty
                          ? report.address
                          : report.addressText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(label: report.status),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final normalized = label.toLowerCase();
    final backgroundColor =
        normalized.contains('complete') || normalized.contains('active')
        ? Colors.green.withValues(alpha: 0.15)
        : normalized.contains('pending') || normalized.contains('inactive')
        ? Colors.orange.withValues(alpha: 0.15)
        : Colors.blue.withValues(alpha: 0.15);
    final foregroundColor =
        normalized.contains('complete') || normalized.contains('active')
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

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(24),
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        _EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Unable to load dashboard data',
          message: message,
          actionLabel: 'Retry',
          onActionPressed: onRetry,
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onActionPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onActionPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (actionLabel != null && onActionPressed != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onActionPressed, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) {
  final date = value.toLocal();
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year;
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day/$month/$year $hour:$minute';
}

String _formatTimeOfDay(String timeString) {
  if (timeString.isEmpty) return 'N/A';
  try {
    final parts = timeString.split(':');
    if (parts.length >= 2) {
      final hour = parts[0].padLeft(2, '0');
      final minute = parts[1].padLeft(2, '0');
      return '$hour:$minute';
    }
  } catch (_) {}
  return timeString;
}
