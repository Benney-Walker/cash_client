import 'package:flutter/material.dart';

import '../theme/app_status_colors.dart';
import 'collector_api.dart';
import 'collector_models.dart';
import 'member_cache.dart';
import 'member_directory.dart';

/// Step 1 of recording a payment (design P1): choose the member.
///
/// Shows the list saved on the phone straight away and downloads a fresh
/// one in the background. Without a connection the saved list still works.
class MemberPickerScreen extends StatefulWidget {
  const MemberPickerScreen({
    super.key,
    required this.directory,
    required this.onMemberChosen,
  });

  final MemberDirectory directory;
  final void Function(BuildContext context, CollectorMember member)
      onMemberChosen;

  @override
  State<MemberPickerScreen> createState() => _MemberPickerScreenState();
}

class _MemberPickerScreenState extends State<MemberPickerScreen> {
  final _search = TextEditingController();

  SavedMembers? _list;
  bool _loading = true;
  String? _refreshError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await widget.directory.saved();
    if (!mounted) return;
    setState(() => _list = saved);
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _refreshError = null;
    });
    try {
      final fresh = await widget.directory.refresh();
      if (!mounted) return;
      setState(() => _list = fresh);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _refreshError = collectorErrorMessage(
          error,
          networkMessage: "Couldn't update the list. Check your connection.",
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;

    return Scaffold(
      appBar: AppBar(title: const Text('Choose member')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              key: const Key('picker.search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Name or account number',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_refreshError != null && list != null)
            _StaleBanner(message: _refreshError!, savedAt: list.savedAt),
          Expanded(child: _buildBody(context, list)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, SavedMembers? list) {
    if (list == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return _Message(
        icon: Icons.cloud_off_outlined,
        title: "Couldn't load your branch's members",
        body: _refreshError ?? 'Try again.',
        action: OutlinedButton.icon(
          key: const Key('picker.retry'),
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
    }
    if (list.members.isEmpty) {
      return const _Message(
        icon: Icons.groups_outlined,
        title: 'No members in your branch yet',
        body: 'Members appear here once the office has registered and '
            'activated them.',
      );
    }

    final matches = searchMembers(list.members, _search.text);
    // Two members can share a name; only then show account numbers, so the
    // collector can tell them apart.
    final nameCounts = <String, int>{};
    for (final m in list.members) {
      nameCounts.update(m.name.toLowerCase(), (n) => n + 1, ifAbsent: () => 1);
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        key: const Key('picker.list'),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: matches.length + 1,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == matches.length) {
            return _SavedFooter(savedAt: list.savedAt, empty: matches.isEmpty);
          }
          final member = matches[index];
          final duplicate = (nameCounts[member.name.toLowerCase()] ?? 0) > 1;
          return ListTile(
            key: Key('picker.member.$index'),
            minVerticalPadding: 12,
            title: Text(member.name),
            subtitle: Text(_accountsLine(member, showNumbers: duplicate)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => widget.onMemberChosen(context, member),
          );
        },
      ),
    );
  }

  static String _accountsLine(CollectorMember member, {required bool showNumbers}) {
    return member.paymentTypes.map((type) {
      final label = type.label;
      if (!showNumbers) return label;
      return '$label ${member.accountFor(type)!.accountNumber}';
    }).join(' · ');
  }
}

class _SavedFooter extends StatelessWidget {
  const _SavedFooter({required this.savedAt, required this.empty});

  final DateTime savedAt;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (empty) ...[
            Text('No member matches that search.',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
          ],
          Text(
            'List saved for offline · updated ${describeSavedAt(savedAt)}',
            key: const Key('picker.savedAt'),
            style: style,
          ),
        ],
      ),
    );
  }
}

/// Shown when a refresh failed but the saved list is still there.
class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.message, required this.savedAt});

  final String message;
  final DateTime savedAt;

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    return Container(
      key: const Key('picker.stale'),
      width: double.infinity,
      color: status.warningContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: status.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$message Showing the list saved ${describeSavedAt(savedAt)}.',
              style: TextStyle(color: status.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "08:12" today, otherwise "14 Nov, 08:12".
String describeSavedAt(DateTime savedAt, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final time = '${savedAt.hour.toString().padLeft(2, '0')}:'
      '${savedAt.minute.toString().padLeft(2, '0')}';
  final sameDay = savedAt.year == today.year &&
      savedAt.month == today.month &&
      savedAt.day == today.day;
  return sameDay ? time : '${savedAt.day} ${_months[savedAt.month - 1]}, $time';
}
