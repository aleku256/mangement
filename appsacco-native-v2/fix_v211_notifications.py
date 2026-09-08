from pathlib import Path

p = Path('/tmp/appsacco_native/lib/main.dart')
s = p.read_text()
start = s.index('class NotificationsPage extends StatefulWidget')
end = s.index('class WithdrawalsPage extends StatefulWidget', start)

replacement = r'''class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.session});
  final SessionController session;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool loading = true;
  bool markingAll = false;
  String? error;
  List<dynamic> items = [];
  String category = 'all';
  final Set<String> busyIds = <String>{};
  final cats = ['all', 'transactions', 'loans', 'announcements', 'promotions'];

  @override
  void initState() {
    super.initState();
    load();
  }

  bool _isUnread(Map<String, dynamic> n) => textOf(n['read_at']).isEmpty;

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final r = await widget.session.api.get(
        '/member/notifications',
        query: {'category': category},
      );
      if (mounted) {
        setState(() {
          items = listOf(mapOf(r['data'])['notifications']);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> allRead() async {
    if (markingAll) return;
    final hasUnread = items.any((x) => _isUnread(mapOf(x)));
    if (!hasUnread) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All notifications are already read.')),
        );
      }
      return;
    }

    setState(() => markingAll = true);
    try {
      await widget.session.api.post('/member/notifications/read-all');
      final now = DateTime.now().toIso8601String();
      if (mounted) {
        setState(() {
          items = items.map((x) {
            final n = mapOf(x);
            return <String, dynamic>{...n, 'read_at': n['read_at'] ?? now};
          }).toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All notifications marked as read.')),
        );
      }
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not mark notifications as read: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => markingAll = false);
    }
  }

  Future<void> read(Map<String, dynamic> n) async {
    if (!_isUnread(n)) return;
    final id = textOf(n['id']);
    if (id.isEmpty || busyIds.contains(id)) return;

    setState(() => busyIds.add(id));
    try {
      await widget.session.api.post('/member/notifications/$id/read');
      final now = DateTime.now().toIso8601String();
      if (mounted) {
        setState(() {
          items = items.map((x) {
            final item = mapOf(x);
            if (textOf(item['id']) == id) {
              return <String, dynamic>{...item, 'read_at': now};
            }
            return item;
          }).toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification marked as read.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not mark notification as read: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => busyIds.remove(id));
    }
  }

  Future<void> _openNotification(Map<String, dynamic> n) async {
    if (_isUnread(n)) await read(n);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                textOf(n['title'], 'Notification'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: kDarkGreen,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                dateText(n['created_at']),
                style: const TextStyle(fontSize: 11, color: Color(0xFF718077)),
              ),
              const SizedBox(height: 14),
              Text(
                textOf(n['message']),
                style: const TextStyle(fontSize: 14, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = items.where((x) => _isUnread(mapOf(x))).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: Column(
        children: [
          const PageHeader(
            title: 'Notifications',
            subtitle: 'Transactions, loans, announcements and promotions.',
          ),
          SizedBox(
            height: 54,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: cats.map((c) => Padding(
                padding: const EdgeInsets.only(right: 7),
                child: ChoiceChip(
                  selected: category == c,
                  label: Text(pretty(c)),
                  onSelected: (_) {
                    setState(() => category = c);
                    load();
                  },
                  selectedColor: kGreen,
                  labelStyle: TextStyle(
                    color: category == c ? Colors.white : kDarkGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: markingAll ? null : allRead,
                icon: markingAll
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.done_all_rounded),
                label: Text(
                  unreadCount == 0
                      ? 'All notifications read'
                      : 'Mark All as Read ($unreadCount)',
                ),
              ),
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: kGreen))
                : error != null
                    ? ErrorPane(message: error!, retry: load)
                    : RefreshIndicator(
                        onRefresh: load,
                        child: items.isEmpty
                            ? const ListView(
                                children: [
                                  SizedBox(height: 160),
                                  EmptyPane(
                                    icon: Icons.notifications_none_rounded,
                                    text: 'No notifications in this category.',
                                  ),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(14),
                                itemCount: items.length,
                                itemBuilder: (_, i) {
                                  final n = mapOf(items[i]);
                                  final unread = _isUnread(n);
                                  final id = textOf(n['id']);
                                  final busy = busyIds.contains(id);
                                  return AppCard(
                                    padding: const EdgeInsets.all(13),
                                    child: InkWell(
                                      onTap: () => _openNotification(n),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  textOf(n['title'], 'Notification'),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    color: kDarkGreen,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              if (unread)
                                                FilledButton(
                                                  onPressed: busy ? null : () => read(n),
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor: kGreen,
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 7,
                                                    ),
                                                    minimumSize: Size.zero,
                                                    tapTargetSize:
                                                        MaterialTapTargetSize.shrinkWrap,
                                                  ),
                                                  child: busy
                                                      ? const SizedBox(
                                                          width: 13,
                                                          height: 13,
                                                          child: CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Colors.white,
                                                          ),
                                                        )
                                                      : const Text(
                                                          'Mark Read',
                                                          style: TextStyle(fontSize: 10),
                                                        ),
                                                )
                                              else
                                                const StatusBadge(text: 'Read'),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            dateText(n['created_at']),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFF718077),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            textOf(n['message']),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              color: Color(0xFF5E6B63),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}

'''

p.write_text(s[:start] + replacement + s[end:])
print('Applied APP SACCO v2.1.1 notification UX fix')
