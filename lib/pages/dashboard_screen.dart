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
  late Future<List<BarangaySummary>> _barangayFuture;
  late Future<List<CollectionLogItem>> _recentLogsFuture;
  late Future<List<CollectionScheduleItem>> _activeSchedulesFuture;
  late Future<List<ResidentReportItem>> _recentReportsFuture;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  void _loadDashboardData() {
    _barangayFuture = _service.fetchBarangaySummaries();
    _recentLogsFuture = _service.fetchRecentCollectionLogs(limit: 5);
    _activeSchedulesFuture = _service.fetchActiveSchedules(limit: 5);
    _recentReportsFuture = _service.fetchRecentReports(limit: 5);
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

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                if (barangays.isEmpty)
                  const _EmptyState(
                    icon: Icons.maps_home_work_outlined,
                    title: 'No collection logs yet',
                    message:
                        'Once Supabase starts returning collection logs, each barangay will appear here with a details button.',
                  )
                else
                  ...barangays.map(
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
                    if (logs.isEmpty) {
                      return const _EmptyState(
                        icon: Icons.inbox_outlined,
                        title: 'No recent logs',
                        message:
                            'When collection logs are added in Supabase, they will appear here.',
                      );
                    }

                    return Column(
                      children: logs
                          .map(
                            (log) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _RecentLogCard(log: log),
                            ),
                          )
                          .toList(),
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
                    if (schedules.isEmpty) {
                      return const _EmptyState(
                        icon: Icons.calendar_month_outlined,
                        title: 'No active schedules',
                        message:
                            'Create active schedules in the details screen to populate this area.',
                      );
                    }

                    return Column(
                      children: schedules
                          .map(
                            (schedule) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _SchedulePreviewCard(schedule: schedule),
                            ),
                          )
                          .toList(),
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
                    if (reports.isEmpty) {
                      return const _EmptyState(
                        icon: Icons.report_outlined,
                        title: 'No recent reports',
                        message:
                            'Resident reports synced from Supabase will show up here.',
                      );
                    }

                    return Column(
                      children: reports
                          .map(
                            (report) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _ReportPreviewCard(report: report),
                            ),
                          )
                          .toList(),
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
  const _RecentLogCard({required this.log});

  final CollectionLogItem log;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
    );
  }
}

class _SchedulePreviewCard extends StatelessWidget {
  const _SchedulePreviewCard({required this.schedule});

  final CollectionScheduleItem schedule;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
    );
  }
}

class _ReportPreviewCard extends StatelessWidget {
  const _ReportPreviewCard({required this.report});

  final ResidentReportItem report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
