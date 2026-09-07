import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

const Color appGreen = Color(0xFF0B6B36);
const Color appDarkGreen = Color(0xFF064A28);
const String memberPortalUrl = 'https://ellnoo.com/member-app';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: appDarkGreen,
    statusBarIconBrightness: Brightness.light,
    navigationBarColor: Colors.white,
    navigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const AppSaccoApp());
}

class AppSaccoApp extends StatelessWidget {
  const AppSaccoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'APP SACCO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: appGreen),
        scaffoldBackgroundColor: const Color(0xFFF4F8F5),
        fontFamilyFallback: const ['Roboto', 'Arial'],
      ),
      home: const MemberPortalScreen(),
    );
  }
}

class MemberPortalScreen extends StatefulWidget {
  const MemberPortalScreen({super.key});

  @override
  State<MemberPortalScreen> createState() => _MemberPortalScreenState();
}

class _MemberPortalScreenState extends State<MemberPortalScreen> {
  InAppWebViewController? _webController;
  late final PullToRefreshController _pullToRefreshController;
  double _progress = 0;
  bool _hasMainFrameError = false;
  String _lastError = '';
  Timer? _slowLoadTimer;
  bool _showSlowLoadHint = false;

  @override
  void initState() {
    super.initState();
    _pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(color: appGreen),
      onRefresh: () async {
        await _webController?.reload();
      },
    );
  }

  @override
  void dispose() {
    _slowLoadTimer?.cancel();
    super.dispose();
  }

  void _startSlowLoadTimer() {
    _slowLoadTimer?.cancel();
    _showSlowLoadHint = false;
    _slowLoadTimer = Timer(const Duration(seconds: 12), () {
      if (mounted && _progress < 1) {
        setState(() => _showSlowLoadHint = true);
      }
    });
  }

  Future<bool> _handleBack() async {
    final controller = _webController;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return false;
    }
    return true;
  }

  Future<void> _openExternal(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool _isExternalScheme(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'tel' ||
        scheme == 'mailto' ||
        scheme == 'sms' ||
        scheme == 'whatsapp' ||
        scheme == 'intent' ||
        scheme == 'market';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleBack,
      child: Scaffold(
        body: SafeArea(
          top: false,
          bottom: false,
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(memberPortalUrl)),
                pullToRefreshController: _pullToRefreshController,
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  cacheEnabled: true,
                  useShouldOverrideUrlLoading: true,
                  useOnDownloadStart: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  supportZoom: false,
                  builtInZoomControls: false,
                  displayZoomControls: false,
                  verticalScrollBarEnabled: false,
                  horizontalScrollBarEnabled: false,
                  transparentBackground: false,
                  userAgent: 'APP-SACCO-Android/2.0 Mobile Flutter WebView',
                ),
                onWebViewCreated: (controller) {
                  _webController = controller;
                  _startSlowLoadTimer();
                },
                onLoadStart: (controller, url) {
                  _startSlowLoadTimer();
                  if (mounted) {
                    setState(() {
                      _hasMainFrameError = false;
                      _lastError = '';
                      _showSlowLoadHint = false;
                    });
                  }
                },
                onProgressChanged: (controller, progress) {
                  if (mounted) {
                    setState(() => _progress = progress / 100.0);
                  }
                  if (progress == 100) {
                    _pullToRefreshController.endRefreshing();
                    _slowLoadTimer?.cancel();
                    if (mounted) setState(() => _showSlowLoadHint = false);
                  }
                },
                onLoadStop: (controller, url) async {
                  _pullToRefreshController.endRefreshing();
                  _slowLoadTimer?.cancel();
                  if (mounted) {
                    setState(() {
                      _progress = 1;
                      _hasMainFrameError = false;
                      _showSlowLoadHint = false;
                    });
                  }
                },
                onReceivedError: (controller, request, error) {
                  _pullToRefreshController.endRefreshing();
                  if (request.isForMainFrame == true && mounted) {
                    setState(() {
                      _hasMainFrameError = true;
                      _lastError = error.description;
                    });
                  }
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final webUri = navigationAction.request.url;
                  if (webUri == null) return NavigationActionPolicy.ALLOW;
                  final uri = Uri.tryParse(webUri.toString());
                  if (uri != null && _isExternalScheme(uri)) {
                    await _openExternal(uri.toString());
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                onDownloadStartRequest: (controller, request) async {
                  await _openExternal(request.url.toString());
                },
                onCreateWindow: (controller, createWindowAction) async {
                  final url = createWindowAction.request.url;
                  if (url != null) {
                    final uri = Uri.tryParse(url.toString());
                    if (uri != null && _isExternalScheme(uri)) {
                      await _openExternal(uri.toString());
                    } else {
                      await controller.loadUrl(urlRequest: URLRequest(url: url));
                    }
                  }
                  return false;
                },
                androidOnPermissionRequest: (controller, origin, resources) async {
                  return PermissionRequestResponse(
                    resources: resources,
                    action: PermissionRequestResponseAction.GRANT,
                  );
                },
              ),
              if (_progress < 1 && !_hasMainFrameError)
                Positioned(
                  left: 0,
                  right: 0,
                  top: MediaQuery.of(context).padding.top,
                  child: LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress,
                    minHeight: 3,
                    color: const Color(0xFFD4AF37),
                    backgroundColor: Colors.transparent,
                  ),
                ),
              if (_showSlowLoadHint && !_hasMainFrameError)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 28,
                  child: _InfoBanner(
                    message: 'Still connecting to APP SACCO…',
                    actionLabel: 'Reload',
                    onAction: () => _webController?.reload(),
                  ),
                ),
              if (_hasMainFrameError)
                Positioned.fill(
                  child: _OfflineView(
                    message: _lastError,
                    onRetry: () {
                      setState(() => _hasMainFrameError = false);
                      _webController?.loadUrl(
                        urlRequest: URLRequest(url: WebUri(memberPortalUrl)),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _OfflineView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF4F8F5),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 108,
              height: 108,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x16000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Image.asset('assets/images/app_sacco_logo.png'),
            ),
            const SizedBox(height: 24),
            const Text(
              'APP SACCO',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: appDarkGreen,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'We could not reach your SACCO account right now. Check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.45, color: Color(0xFF52605A)),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFF7C8782)),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: appGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(
                  'Try Again',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _InfoBanner({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: appDarkGreen,
      borderRadius: BorderRadius.circular(18),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            const Icon(Icons.cloud_sync_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel,
                style: const TextStyle(color: Color(0xFFFFD86E), fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
