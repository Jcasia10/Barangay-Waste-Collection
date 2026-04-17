import 'dart:async';

import 'package:exam/services/admin_dashboard_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MyAccountScreen extends StatefulWidget {
  const MyAccountScreen({super.key});

  @override
  State<MyAccountScreen> createState() => _MyAccountScreenState();
}

class _MyAccountScreenState extends State<MyAccountScreen> {
  final AdminDashboardService _service = AdminDashboardService();
  static const Duration _realtimeRefreshDebounceDuration = Duration(
    milliseconds: 300,
  );
  final List<RealtimeChannel> _realtimeChannels = <RealtimeChannel>[];
  Timer? _realtimeRefreshDebounce;
  late Future<CurrentUserProfile> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _service.fetchCurrentUserProfile();
    _subscribeToRealtimeChanges();
  }

  void _subscribeToRealtimeChanges() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      return;
    }

    final userChannel = Supabase.instance.client.channel('account-user-$userId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: AdminDashboardService.usersTable,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: userId,
        ),
        callback: (_) => _scheduleRealtimeRefresh(),
      )
      ..subscribe();

    final barangayChannel =
        Supabase.instance.client.channel('account-barangay-$userId')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: AdminDashboardService.barangayTable,
            callback: (_) => _scheduleRealtimeRefresh(),
          )
          ..subscribe();

    _realtimeChannels
      ..add(userChannel)
      ..add(barangayChannel);
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

      setState(() {
        _profileFuture = _service.fetchCurrentUserProfile();
      });
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _profileFuture = _service.fetchCurrentUserProfile();
    });
    await _profileFuture;
  }

  Future<void> _openEditProfile(CurrentUserProfile profile) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditProfileSheet(
        initialPhone: profile.phone,
        initialAddress: profile.address,
        initialBarangayId: profile.barangayId,
        loadBarangays: _service.fetchBarangayOptions,
        onSave: (phone, address, barangayId) =>
            _service.updateCurrentUserProfile(
              phone: phone,
              address: address,
              barangayId: barangayId,
            ),
      ),
    );

    if (saved == true && mounted) {
      await _refresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
    }
  }

  @override
  void dispose() {
    _realtimeRefreshDebounce?.cancel();
    for (final channel in _realtimeChannels) {
      Supabase.instance.client.removeChannel(channel);
    }
    _realtimeChannels.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Account'),
        actions: [
          IconButton(
            tooltip: 'Refresh profile',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<CurrentUserProfile>(
          future: _profileFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Unable to load your account details.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              );
            }

            final profile = snapshot.data;
            if (profile == null) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No account details available.')),
                ],
              );
            }

            final barangayLabel = [
              profile.barangayName,
              profile.barangayDistrict,
              profile.barangayCity,
            ].where((part) => part.trim().isNotEmpty).join(' • ');

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => _openEditProfile(profile),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit profile'),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: scheme.primaryContainer,
                        child: Text(
                          _buildInitials(profile.fullName),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.fullName,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              profile.email.isEmpty
                                  ? 'No email provided'
                                  : profile.email,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _InfoTile(
                  label: 'Role',
                  value: _displayValue(profile.role),
                  icon: Icons.badge_outlined,
                ),
                _InfoTile(
                  label: 'Phone',
                  value: _displayValue(profile.phone),
                  icon: Icons.phone_outlined,
                ),
                _InfoTile(
                  label: 'Address',
                  value: _displayValue(profile.address),
                  icon: Icons.home_outlined,
                ),
                _InfoTile(
                  label: 'Barangay',
                  value: _displayValue(barangayLabel),
                  icon: Icons.location_city_outlined,
                ),
                _InfoTile(
                  label: 'User ID',
                  value: _displayValue(profile.id),
                  icon: Icons.fingerprint,
                ),
                _InfoTile(
                  label: 'Created',
                  value: _formatDateTime(profile.createdAt),
                  icon: Icons.event_available_outlined,
                ),
                _InfoTile(
                  label: 'Last updated',
                  value: _formatDateTime(profile.updatedAt),
                  icon: Icons.update_outlined,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _buildInitials(String value) {
    final parts = value
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part.trim())
        .toList();

    if (parts.isEmpty) {
      return 'U';
    }

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  String _displayValue(String value) {
    return value.trim().isEmpty ? 'Not provided' : value;
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'Not available';
    }

    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.initialPhone,
    required this.initialAddress,
    required this.initialBarangayId,
    required this.loadBarangays,
    required this.onSave,
  });

  final String initialPhone;
  final String initialAddress;
  final int? initialBarangayId;
  final Future<List<BarangayRow>> Function() loadBarangays;
  final Future<void> Function(String phone, String address, int? barangayId)
  onSave;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late Future<List<BarangayRow>> _barangaysFuture;
  int? _selectedBarangayId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.initialPhone);
    _addressController = TextEditingController(text: widget.initialAddress);
    _selectedBarangayId = widget.initialBarangayId;
    _barangaysFuture = widget.loadBarangays();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    setState(() {
      _isSaving = true;
    });

    try {
      await widget.onSave(
        _phoneController.text,
        _addressController.text,
        _selectedBarangayId,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message.isNotEmpty
                ? error.message
                : 'Unable to update profile.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update profile: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
              'Edit profile',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<BarangayRow>>(
              future: _barangaysFuture,
              builder: (context, snapshot) {
                final options = snapshot.data ?? const <BarangayRow>[];
                final selectedExists = options.any(
                  (item) => item.id == _selectedBarangayId,
                );
                final effectiveSelectedId = selectedExists
                    ? _selectedBarangayId
                    : null;

                return DropdownButtonFormField<int?>(
                  initialValue: effectiveSelectedId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Barangay',
                    helperText:
                        snapshot.connectionState == ConnectionState.waiting
                        ? 'Loading barangays...'
                        : 'Select your barangay',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Not set'),
                    ),
                    ...options.map(
                      (barangay) => DropdownMenuItem<int?>(
                        value: barangay.id,
                        child: Text(
                          '${barangay.name} (${barangay.district.isEmpty ? 'No district' : barangay.district})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          setState(() {
                            _selectedBarangayId = value;
                          });
                        },
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _isSaving ? null : _saveChanges,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save changes'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
