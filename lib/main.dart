import 'package:flutter/material.dart';

import 'onboarding.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'models.dart';
import 'store.dart';

void main() => runApp(AjoApp(store: AjoStore()..load()));

const _green = Color(0xFF16A34A);
final _naira = NumberFormat.currency(locale: 'en_NG', symbol: '₦', decimalDigits: 0);
final _date = DateFormat('EEE d MMM');

class AjoApp extends StatelessWidget {
  const AjoApp({super.key, required this.store});
  final AjoStore store;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: _green, brightness: b));
    return MaterialApp(
      title: 'Ajo',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: OnboardingGate(
        color: _green,
        slides: const [
          Slide(Icons.groups_outlined, 'Run your ajo without the notebook', 'Set up a group, add members in payout order, and Ajo works out every due date.'),
          Slide(Icons.fact_check_outlined, 'See who has paid at a glance', 'Tick contributions each cycle and know exactly who still owes.'),
          Slide(Icons.ios_share, 'Share the ledger', 'Send everyone the current cycle and schedule in one tap.'),
        ],
        child: GroupsScreen(store: store),
      ),
    );
  }
}

/// All savings groups.
class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key, required this.store});
  final AjoStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final now = DateTime.now();
        return Scaffold(
          appBar: AppBar(title: const Text('Ajo', style: TextStyle(fontWeight: FontWeight.w800))),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreateGroupScreen(store: store))),
            icon: const Icon(Icons.add),
            label: const Text('New group'),
          ),
          body: !store.ready
              ? const Center(child: CircularProgressIndicator())
              : store.groups.isEmpty
                  ? const _Empty()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      children: [
                        for (final g in store.groups)
                          Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(_summary(g, now)),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupScreen(store: store, groupId: g.id))),
                            ),
                          ),
                      ],
                    ),
        );
      },
    );
  }

  String _summary(AjoGroup g, DateTime now) {
    final c = g.currentCycle(now);
    if (g.finished) return 'Round complete · ${g.members.length} members';
    if (c < 0) return 'Starts ${_date.format(g.start)} · ${_naira.format(g.amount)} ${g.frequency.name}';
    return '${g.recipient(c).name} collects ${_naira.format(g.pot)} · ${g.paidCount(c)}/${g.members.length} paid';
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.savings_outlined, size: 64, color: _green),
            const SizedBox(height: 16),
            Text('No groups yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Start an ajo: everyone contributes each week or month, and one person collects the pot each time.', textAlign: TextAlign.center),
          ]),
        ),
      );
}

/// Create a group: name, amount, frequency, start date and payout order.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key, required this.store});
  final AjoStore store;

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _member = TextEditingController();
  final _members = <Member>[];
  var _frequency = Frequency.monthly;
  var _start = DateTime.now();

  bool get _valid => _name.text.trim().isNotEmpty && (int.tryParse(_amount.text) ?? 0) > 0 && _members.length >= 2;

  void _addMember() {
    final name = _member.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _members.add(Member(id: '${DateTime.now().microsecondsSinceEpoch}', name: name));
      _member.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final amount = int.tryParse(_amount.text) ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('New ajo group')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Group name', hintText: 'e.g. Office ajo'), onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Contribution per person (₦)', prefixText: '₦ '),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          SegmentedButton<Frequency>(
            segments: const [ButtonSegment(value: Frequency.weekly, label: Text('Weekly')), ButtonSegment(value: Frequency.monthly, label: Text('Monthly'))],
            selected: {_frequency},
            onSelectionChanged: (s) => setState(() => _frequency = s.first),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: const Text('First collection'),
            subtitle: Text(_date.format(_start)),
            onTap: () async {
              final picked = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (picked != null) setState(() => _start = picked);
            },
          ),
          const Divider(),
          Text('Members — in payout order', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Drag to reorder. The first person collects first.'),
          Row(children: [
            Expanded(child: TextField(controller: _member, decoration: const InputDecoration(hintText: 'Member name'), onSubmitted: (_) => _addMember())),
            IconButton.filled(onPressed: _addMember, icon: const Icon(Icons.person_add)),
          ]),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // onReorderItem already adjusts newIndex for the removed item.
            onReorderItem: (oldIndex, newIndex) => setState(() => _members.insert(newIndex, _members.removeAt(oldIndex))),
            children: [
              for (var i = 0; i < _members.length; i++)
                ListTile(
                  key: ValueKey(_members[i].id),
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text(_members[i].name),
                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _members.removeAt(i))),
                ),
            ],
          ),
          if (_members.length >= 2 && amount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Each ${_frequency == Frequency.weekly ? 'week' : 'month'}, one person collects ${_naira.format(amount * _members.length)}.',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: !_valid
                ? null
                : () {
                    widget.store.upsert(AjoGroup(
                      id: '${DateTime.now().millisecondsSinceEpoch}',
                      name: _name.text.trim(),
                      amount: amount,
                      frequency: _frequency,
                      start: DateTime(_start.year, _start.month, _start.day),
                      members: List.of(_members),
                    ));
                    Navigator.pop(context);
                  },
            child: const Text('Create group'),
          ),
        ],
      ),
    );
  }
}

/// One group: this cycle's collection, who has paid, and the full schedule.
class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key, required this.store, required this.groupId});
  final AjoStore store;
  final String groupId;

  String _ledger(AjoGroup g, int cycle) {
    final b = StringBuffer('${g.name} — ${_naira.format(g.amount)} ${g.frequency.name}\n');
    if (cycle >= 0) {
      b.writeln('Now: ${g.recipient(cycle).name} collects ${_naira.format(g.pot)} on ${_date.format(g.dueDate(cycle))}');
      b.writeln('Paid (${g.paidCount(cycle)}/${g.members.length}): ${g.members.where((m) => g.hasPaid(cycle, m.id)).map((m) => m.name).join(', ')}');
      final owing = g.owing(cycle);
      if (owing.isNotEmpty) b.writeln('Still owing: ${owing.map((m) => m.name).join(', ')}');
    }
    b.writeln('\nSchedule:');
    for (var i = 0; i < g.cycles; i++) {
      b.writeln('${i + 1}. ${_date.format(g.dueDate(i))} — ${g.recipient(i).name}${g.collected.contains(i) ? ' ✓' : ''}');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final g = store.byId(groupId);
        if (g == null) return const Scaffold();
        final now = DateTime.now();
        final current = g.currentCycle(now);
        final cycle = current < 0 ? 0 : current;
        return Scaffold(
          appBar: AppBar(
            title: Text(g.name),
            actions: [
              IconButton(
                tooltip: 'Share ledger',
                icon: const Icon(Icons.share),
                onPressed: () => SharePlus.instance.share(ShareParams(text: _ledger(g, current))),
              ),
              IconButton(
                tooltip: 'Delete group',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('Delete this group?'),
                      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete'))],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    await store.remove(g.id);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: _green,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(current < 0 ? 'STARTS ${_date.format(g.start).toUpperCase()}' : 'CYCLE ${cycle + 1} OF ${g.cycles} · ${_date.format(g.dueDate(cycle)).toUpperCase()}',
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Text('${g.recipient(cycle).name} collects', style: const TextStyle(color: Colors.white, fontSize: 18)),
                    Text(_naira.format(g.pot), style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: g.paidCount(cycle) / g.members.length,
                      backgroundColor: Colors.white24,
                      color: Colors.white,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 6),
                    Text('${_naira.format(g.collectedSoFar(cycle))} in · ${g.paidCount(cycle)}/${g.members.length} paid', style: const TextStyle(color: Colors.white)),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Text('Who has paid this cycle', style: Theme.of(context).textTheme.titleMedium),
              for (final m in g.members)
                CheckboxListTile(
                  value: g.hasPaid(cycle, m.id),
                  onChanged: (_) => store.upsert(g.togglePaid(cycle, m.id)),
                  title: Text(m.name),
                  secondary: g.recipient(cycle).id == m.id ? const Chip(label: Text('Collecting')) : null,
                ),
              if (g.isComplete(cycle) && !g.collected.contains(cycle))
                FilledButton.icon(
                  onPressed: () => store.upsert(g.toggleCollected(cycle)),
                  icon: const Icon(Icons.check),
                  label: Text('Mark pot handed to ${g.recipient(cycle).name}'),
                ),
              const SizedBox(height: 16),
              Text('Schedule', style: Theme.of(context).textTheme.titleMedium),
              for (var i = 0; i < g.cycles; i++)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: g.collected.contains(i) ? _green : null,
                    child: g.collected.contains(i) ? const Icon(Icons.check, color: Colors.white) : Text('${i + 1}'),
                  ),
                  title: Text(g.recipient(i).name),
                  subtitle: Text(_date.format(g.dueDate(i))),
                  trailing: i == current ? const Text('NOW', style: TextStyle(color: _green, fontWeight: FontWeight.w800)) : null,
                ),
            ],
          ),
        );
      },
    );
  }
}
