import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'store.dart';
import 'sync.dart';

/// The cloud button on the groups list: shows whether everything is backed up.
class SyncButton extends StatelessWidget {
  const SyncButton({super.key, required this.store});
  final AjoStore store;

  @override
  Widget build(BuildContext context) {
    final sync = store.sync;
    if (sync == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final (icon, label) = !sync.signedIn
            ? (Icons.cloud_off_outlined, 'Not backed up. Sign in to sync')
            : sync.syncing
                ? (Icons.cloud_sync_outlined, 'Syncing')
                : sync.pendingCount > 0
                    ? (Icons.cloud_upload_outlined, '${sync.pendingCount} change(s) waiting to sync')
                    : (Icons.cloud_done_outlined, 'All changes synced');
        return IconButton(
          tooltip: label,
          icon: Badge(
            isLabelVisible: sync.signedIn && sync.pendingCount > 0 && !sync.syncing,
            label: Text('${sync.pendingCount}'),
            child: Icon(icon),
          ),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SyncScreen(store: store))),
        );
      },
    );
  }
}

/// Account & sync: sign in or create an account, choose the server, sync now.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key, required this.store});
  final AjoStore store;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final TextEditingController _server = TextEditingController(text: widget.store.sync!.baseUrl);
  bool _creating = false;
  bool _busy = false;
  String? _error;

  SyncService get _sync => widget.store.sync!;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _server]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _sync.setBaseUrl(_server.text);
      if (_creating) {
        await _sync.register(_name.text, _email.text, _password.text);
      } else {
        await _sync.signIn(_email.text, _password.text);
      }
      _password.clear();
      await widget.store.syncNow();
    } on AjoApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Couldn’t reach the server. Check the address and your connection.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _sync,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Account & sync')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: _sync.signedIn ? _signedIn(context) : _signedOut(context),
        ),
      ),
    );
  }

  List<Widget> _signedIn(BuildContext context) {
    final s = _sync.session!;
    final when = _sync.lastSynced == null ? 'Not yet' : DateFormat('EEE d MMM, h:mm a').format(_sync.lastSynced!);
    return [
      Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(s.email),
        ),
      ),
      const SizedBox(height: 12),
      ListTile(
        leading: Icon(_sync.pendingCount == 0 ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined),
        title: Text(_sync.pendingCount == 0 ? 'All changes synced' : '${_sync.pendingCount} change(s) waiting to sync'),
        subtitle: Text('Last synced: $when'),
      ),
      if (_sync.lastError != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(_sync.lastError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _sync.syncing ? null : () => widget.store.syncNow(),
        icon: const Icon(Icons.sync),
        label: Text(_sync.syncing ? 'Syncing…' : 'Sync now'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: () => _sync.signOut(),
        child: const Text('Sign out'),
      ),
      const SizedBox(height: 24),
      Text('Server: ${_sync.baseUrl}', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Text('Your groups stay on this phone when you sign out.', style: Theme.of(context).textTheme.bodySmall),
    ];
  }

  List<Widget> _signedOut(BuildContext context) {
    return [
      Text(
        _creating ? 'Create an account' : 'Sign in to back up your groups',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      const Text('Ajo works without an account. Sign in to keep a copy of your groups on the server and use them on another phone.'),
      const SizedBox(height: 20),
      if (_creating) ...[
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Your name', border: OutlineInputBorder())),
        const SizedBox(height: 12),
      ],
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        obscureText: true,
        decoration: InputDecoration(
          labelText: 'Password',
          helperText: _creating ? 'At least 8 characters' : null,
          border: const OutlineInputBorder(),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(_busy ? 'Please wait…' : (_creating ? 'Create account' : 'Sign in')),
      ),
      TextButton(
        onPressed: _busy ? null : () => setState(() => _creating = !_creating),
        child: Text(_creating ? 'I already have an account' : 'Create an account'),
      ),
      const SizedBox(height: 16),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Server'),
        subtitle: Text(_sync.baseUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
        children: [
          TextField(
            controller: _server,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'API address',
              helperText: 'For example https://ajo.example.com/api',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ];
  }
}
