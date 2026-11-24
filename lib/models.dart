/// Ajo / esusu: a group contributes a fixed amount every period, and each
/// period one member (in agreed order) collects the whole pot.
library;

enum Frequency { weekly, monthly }

class Member {
  Member({required this.id, required this.name, this.phone = ''});
  final String id;
  final String name;
  final String phone;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone};
  factory Member.fromJson(Map<String, dynamic> j) => Member(id: j['id'] as String, name: j['name'] as String, phone: (j['phone'] ?? '') as String);
}

class AjoGroup {
  AjoGroup({
    required this.id,
    required this.name,
    required this.amount,
    required this.frequency,
    required this.start,
    required this.members,
    Map<int, Set<String>>? paid,
    Set<int>? collected,
    this.updatedAt,
  })  : paid = paid ?? {},
        collected = collected ?? {};

  final String id;
  final String name;

  /// Contribution per member per cycle, in naira.
  final int amount;
  final Frequency frequency;
  final DateTime start;

  /// Payout order: member at index i collects in cycle i.
  final List<Member> members;

  /// cycle index → ids of members who have paid that cycle.
  final Map<int, Set<String>> paid;

  /// cycles whose pot has been handed to the recipient.
  final Set<int> collected;

  /// When this copy was last changed (UTC). Used to sync: the newer copy wins.
  final DateTime? updatedAt;

  int get cycles => members.length;
  int get pot => amount * members.length;

  DateTime dueDate(int cycle) => frequency == Frequency.weekly
      ? start.add(Duration(days: 7 * cycle))
      : DateTime(start.year, start.month + cycle, start.day.clamp(1, 28));

  Member recipient(int cycle) => members[cycle % members.length];

  /// The cycle we're in today (clamped to the round), or -1 before it starts.
  int currentCycle(DateTime now) {
    if (now.isBefore(start)) return -1;
    var c = 0;
    while (c < cycles - 1 && !now.isBefore(dueDate(c + 1))) {
      c++;
    }
    return c;
  }

  bool hasPaid(int cycle, String memberId) => paid[cycle]?.contains(memberId) ?? false;
  int paidCount(int cycle) => paid[cycle]?.length ?? 0;
  int collectedSoFar(int cycle) => paidCount(cycle) * amount;
  bool isComplete(int cycle) => paidCount(cycle) == members.length;
  bool get finished => collected.length == cycles;

  /// Members who still owe for a cycle — handy for reminders.
  List<Member> owing(int cycle) => members.where((m) => !hasPaid(cycle, m.id)).toList();

  AjoGroup togglePaid(int cycle, String memberId) {
    final next = {for (final e in paid.entries) e.key: {...e.value}};
    final set = next.putIfAbsent(cycle, () => <String>{});
    set.contains(memberId) ? set.remove(memberId) : set.add(memberId);
    return copyWith(paid: next);
  }

  AjoGroup toggleCollected(int cycle) {
    final next = {...collected};
    next.contains(cycle) ? next.remove(cycle) : next.add(cycle);
    return copyWith(collected: next);
  }

  /// The same group, stamped as changed at [at].
  AjoGroup touched(DateTime at) => AjoGroup(
        id: id,
        name: name,
        amount: amount,
        frequency: frequency,
        start: start,
        members: members,
        paid: paid,
        collected: collected,
        updatedAt: at.toUtc(),
      );

  /// True when this copy is newer than [other] (a copy with no stamp is oldest).
  bool isNewerThan(AjoGroup other) {
    final a = updatedAt, b = other.updatedAt;
    if (a == null) return false;
    if (b == null) return true;
    return a.isAfter(b);
  }

  AjoGroup copyWith({Map<int, Set<String>>? paid, Set<int>? collected}) => AjoGroup(
        id: id,
        name: name,
        amount: amount,
        frequency: frequency,
        start: start,
        members: members,
        paid: paid ?? this.paid,
        collected: collected ?? this.collected,
        updatedAt: updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'amount': amount,
        'frequency': frequency.name,
        'start': start.toIso8601String(),
        'members': members.map((m) => m.toJson()).toList(),
        'paid': paid.map((k, v) => MapEntry('$k', v.toList())),
        'collected': collected.toList(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
      };

  factory AjoGroup.fromJson(Map<String, dynamic> j) => AjoGroup(
        id: j['id'] as String,
        name: j['name'] as String,
        amount: j['amount'] as int,
        frequency: Frequency.values.byName(j['frequency'] as String),
        start: DateTime.parse(j['start'] as String),
        members: (j['members'] as List).cast<Map<String, dynamic>>().map(Member.fromJson).toList(),
        paid: j['paid'] is Map
            ? (j['paid'] as Map<String, dynamic>).map((k, v) => MapEntry(int.parse(k), (v as List).cast<String>().toSet()))
            : <int, Set<String>>{},
        collected: (j['collected'] as List).cast<int>().toSet(),
        updatedAt: j['updatedAt'] == null ? null : DateTime.parse(j['updatedAt'] as String).toUtc(),
      );
}
