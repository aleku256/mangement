from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()

s = s.replace(
    "const _portalUrl = 'https://ellnoo.com/member-app';",
    "const _portalUrl = 'https://ellnoo.com/member-app';\nconst _nativeLogoutUrl = 'https://ellnoo.com/member-app/native-logout';",
)

marker = "  Future<bool> _handleBack() async {"
methods = r'''  Future<void> _goHome() async {
    await _controller.loadRequest(Uri.parse(_portalUrl));
  }

  Future<void> _logout() async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to access your APP SACCO account.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _appGreen),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _controller.loadRequest(Uri.parse(_nativeLogoutUrl));
    }
  }

  Future<void> _openNativeMenu() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    ClipOval(
                      child: Image.asset('assets/app_sacco_logo.png', width: 44, height: 44, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('APP SACCO', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _appDarkGreen)),
                          Text('Member App', style: TextStyle(fontSize: 12.5, color: Color(0xFF68806F))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.home_rounded, color: _appGreen),
                  title: const Text('Home'),
                  subtitle: const Text('Return to your member dashboard'),
                  onTap: () { Navigator.pop(sheetContext); _goHome(); },
                ),
                ListTile(
                  leading: const Icon(Icons.refresh_rounded, color: _appGreen),
                  title: const Text('Refresh'),
                  subtitle: const Text('Reload the current page'),
                  onTap: () { Navigator.pop(sheetContext); _reload(); },
                ),
                ListTile(
                  leading: const Icon(Icons.logout_rounded, color: Colors.red),
                  title: const Text('Logout', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800)),
                  subtitle: const Text('Sign out securely from this device'),
                  onTap: () { Navigator.pop(sheetContext); _logout(); },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

'''
if marker not in s:
    raise SystemExit('Back-handler marker not found')
s = s.replace(marker, methods + marker, 1)

scaffold = """      child: Scaffold(\n        body: SafeArea("""
replacement = """      child: Scaffold(\n        floatingActionButton: Padding(\n          padding: const EdgeInsets.only(bottom: 78),\n          child: FloatingActionButton.small(\n            heroTag: 'appsacco_native_menu',\n            onPressed: _openNativeMenu,\n            backgroundColor: _appGreen,\n            foregroundColor: Colors.white,\n            tooltip: 'APP SACCO menu',\n            child: const Icon(Icons.more_horiz_rounded),\n          ),\n        ),\n        body: SafeArea("""
if scaffold not in s:
    raise SystemExit('Scaffold marker not found')
s = s.replace(scaffold, replacement, 1)

p.write_text(s)
print('Native APP SACCO menu patch applied')
