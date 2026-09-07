import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _green = Color(0xFF087B3B);
const _darkGreen = Color(0xFF04582A);
const _portal = 'https://ellnoo.com/member-app';
const _logout = 'https://ellnoo.com/member-app/native-logout';

enum AppAction { home, refresh, logout }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const AppSaccoIOS());
}

class AppSaccoIOS extends StatelessWidget {
  const AppSaccoIOS({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'APP SACCO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _green),
        scaffoldBackgroundColor: const Color(0xFFF4FBF6),
      ),
      home: const MemberPortal(),
    );
  }
}

class MemberPortal extends StatefulWidget {
  const MemberPortal({super.key});

  @override
  State<MemberPortal> createState() => _MemberPortalState();
}

class _MemberPortalState extends State<MemberPortal> {
  late final WebViewController controller;
  bool ready = false;
  bool failed = false;
  int progress = 0;
  String error = '';
  String currentUrl = _portal;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF4FBF6))
      ..enableZoom(false)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => progress = value);
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              currentUrl = url;
              failed = false;
              error = '';
            });
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            setState(() {
              currentUrl = url;
              ready = true;
              progress = 100;
            });
            try {
              await controller.runJavaScript('''
                (function(){
                  var v=document.querySelector('meta[name="viewport"]');
                  if(!v){v=document.createElement('meta');v.name='viewport';document.head.appendChild(v);}
                  v.content='width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no';
                  document.documentElement.style.webkitTextSizeAdjust='100%';
                })();
              ''');
            } catch (_) {}
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && mounted) {
              setState(() {
                failed = true;
                ready = true;
                error = e.description;
              });
            }
          },
          onNavigationRequest: (request) async {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.scheme == 'http' || uri.scheme == 'https') {
              if (uri.host == 'ellnoo.com' || uri.host.endsWith('.ellnoo.com')) {
                return NavigationDecision.navigate;
              }
              try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
              return NavigationDecision.prevent;
            }
            if ({'tel', 'mailto', 'sms', 'whatsapp'}.contains(uri.scheme)) {
              try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(_portal));
  }

  Future<void> doAction(AppAction action) async {
    switch (action) {
      case AppAction.home:
        await controller.loadRequest(Uri.parse(_portal));
        return;
      case AppAction.refresh:
        await controller.reload();
        return;
      case AppAction.logout:
        await confirmLogout();
        return;
    }
  }

  Future<void> confirmLogout() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to access APP SACCO.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _green),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (yes == true) await controller.loadRequest(Uri.parse(_logout));
  }

  Future<void> retry() async {
    if (mounted) setState(() { failed = false; progress = 0; });
    await controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    final onLogin = Uri.tryParse(currentUrl)?.path.startsWith('/login') == true;
    return Scaffold(
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Positioned.fill(child: WebViewWidget(controller: controller)),
            if (!ready) Positioned.fill(child: _Launch(progress: progress)),
            if (failed) Positioned.fill(child: _Offline(details: error, retry: retry)),
            if (ready && !failed && progress < 100)
              Positioned(
                top: MediaQuery.paddingOf(context).top,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: progress == 0 ? null : progress / 100,
                  minHeight: 2.5,
                  color: _green,
                  backgroundColor: const Color(0xFFE4F3E9),
                ),
              ),
            if (ready && !failed && !onLogin)
              Positioned(
                right: 14,
                bottom: 82 + MediaQuery.paddingOf(context).bottom,
                child: Material(
                  elevation: 8,
                  color: _green,
                  shape: const CircleBorder(),
                  child: PopupMenuButton<AppAction>(
                    tooltip: 'APP SACCO menu',
                    onSelected: doAction,
                    icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: AppAction.home, child: ListTile(leading: Icon(Icons.home_rounded), title: Text('Home'))),
                      PopupMenuItem(value: AppAction.refresh, child: ListTile(leading: Icon(Icons.refresh_rounded), title: Text('Refresh'))),
                      PopupMenuDivider(),
                      PopupMenuItem(value: AppAction.logout, child: ListTile(leading: Icon(Icons.logout_rounded), title: Text('Logout'))),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Launch extends StatelessWidget {
  const _Launch({required this.progress});
  final int progress;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF4FBF6),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 128,
                  height: 128,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(.10), blurRadius: 24, offset: const Offset(0, 10))],
                  ),
                  child: ClipOval(child: Image.asset('assets/app_sacco_logo.png', fit: BoxFit.cover)),
                ),
                const SizedBox(height: 24),
                const Text('APP SACCO', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: _darkGreen)),
                const SizedBox(height: 7),
                const Text('Save Together, Grow Together', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF56735F))),
                const SizedBox(height: 34),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress == 0 ? null : progress / 100,
                    minHeight: 6,
                    color: _green,
                    backgroundColor: const Color(0xFFDDEFE3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Offline extends StatelessWidget {
  const _Offline({required this.details, required this.retry});
  final String details;
  final Future<void> Function() retry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF4FBF6),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/app_sacco_logo.png', width: 96, height: 96),
                const SizedBox(height: 22),
                const Text('Unable to open APP SACCO', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _darkGreen)),
                const SizedBox(height: 10),
                const Text('Check your internet connection and try again. Your account remains safe.', textAlign: TextAlign.center),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(details, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(onPressed: retry, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
