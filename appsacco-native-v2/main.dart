import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const kGreen = Color(0xFF087A3E);
const kDarkGreen = Color(0xFF064C2D);
const kBg = Color(0xFFF4FAF6);
const kApiBase = 'https://ellnoo.com/appsacco-api/v1';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppSacco());
}

Map<String, dynamic> mapOf(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return <String, dynamic>{};
}

List<dynamic> listOf(dynamic value) => value is List ? value : <dynamic>[];

String textOf(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  final s = value.toString().trim();
  return s.isEmpty ? fallback : s;
}

double numOf(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(textOf(value)) ?? 0;
}

String money(dynamic value, String currency) {
  final amount = numOf(value);
  return '$currency ${NumberFormat('#,##0').format(amount)}';
}

String dateText(dynamic value) {
  final s = textOf(value);
  if (s.isEmpty) return '-';
  final parsed = DateTime.tryParse(s);
  if (parsed != null) return DateFormat('dd MMM yyyy').format(parsed.toLocal());
  return s.length >= 10 ? s.substring(0, 10) : s;
}

String pretty(dynamic value) {
  final s = textOf(value, '-').replaceAll('_', ' ').replaceAll('-', ' ');
  return s.split(' ').where((e) => e.isNotEmpty).map((e) {
    return '${e[0].toUpperCase()}${e.substring(1).toLowerCase()}';
  }).join(' ');
}

class ApiException implements Exception {
  const ApiException(this.message, [this.status]);
  final String message;
  final int? status;

  @override
  String toString() => message;
}

class ApiClient {
  String? token;

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) {
    return _request('GET', path, query: query);
  }

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) {
    return _request('POST', path, body: body);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    var uri = Uri.parse('$kApiBase$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (token != null && token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    http.Response response;
    try {
      response = method == 'POST'
          ? await http.post(uri, headers: headers, body: jsonEncode(body ?? <String, dynamic>{})).timeout(const Duration(seconds: 25))
          : await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const ApiException('Unable to connect to APP SACCO. Check your internet connection and try again.');
    }

    Map<String, dynamic> payload = <String, dynamic>{};
    try {
      payload = mapOf(jsonDecode(response.body));
    } catch (_) {
      throw ApiException('Server returned an unexpected response (${response.statusCode}).', response.statusCode);
    }

    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] == false) {
      var message = textOf(payload['message'], 'Request failed (${response.statusCode}).');
      final errors = mapOf(payload['errors']);
      if (errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) message = textOf(first.first, message);
        if (first is String) message = first;
      }
      throw ApiException(message, response.statusCode);
    }

    return payload;
  }
}

class SessionController extends ChangeNotifier {
  final ApiClient api = ApiClient();
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  bool booting = true;
  bool authenticated = false;
  Map<String, dynamic> identity = <String, dynamic>{};

  Map<String, dynamic> get user => mapOf(identity['user']);
  Map<String, dynamic> get tenant => mapOf(identity['tenant']);
  Map<String, dynamic> get member => mapOf(identity['member']);
  String get currency => textOf(tenant['currency'], 'UGX').toUpperCase();
  String get name {
    final memberName = textOf(member['member_name']);
    if (memberName.isNotEmpty) return memberName;
    return textOf(user['name'], 'Member');
  }
  String get memberNo => textOf(member['member_no'], 'APP SACCO');

  Future<void> bootstrap() async {
    final saved = await storage.read(key: 'appsacco_token');
    if (saved != null && saved.isNotEmpty) {
      api.token = saved;
      try {
        final result = await api.get('/me');
        identity = mapOf(result['data']);
        authenticated = textOf(user['role_kind']) == 'member';
        if (!authenticated) await storage.delete(key: 'appsacco_token');
      } catch (_) {
        await storage.delete(key: 'appsacco_token');
        api.token = null;
      }
    }
    booting = false;
    notifyListeners();
  }

  Future<void> login(String login, String password) async {
    final result = await api.post('/login', body: {
      'login': login.trim(),
      'password': password,
      'device_name': 'APP SACCO Android',
    });
    final data = mapOf(result['data']);
    final token = textOf(data['access_token']);
    if (token.isEmpty) throw const ApiException('Login succeeded but no access token was returned.');

    identity = mapOf(data['identity']);
    if (textOf(mapOf(identity['user'])['role_kind']) != 'member') {
      throw const ApiException('This APP SACCO build is currently for member accounts.');
    }
    api.token = token;
    await storage.write(key: 'appsacco_token', value: token);
    authenticated = true;
    notifyListeners();
  }

  Future<void> refreshIdentity() async {
    final result = await api.get('/me');
    identity = mapOf(result['data']);
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.post('/logout');
    } catch (_) {}
    await storage.delete(key: 'appsacco_token');
    api.token = null;
    identity = <String, dynamic>{};
    authenticated = false;
    notifyListeners();
  }
}

class AppSacco extends StatefulWidget {
  const AppSacco({super.key});

  @override
  State<AppSacco> createState() => _AppSaccoState();
}

class _AppSaccoState extends State<AppSacco> {
  late final SessionController session;

  @override
  void initState() {
    super.initState();
    session = SessionController();
    session.bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'APP SACCO',
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: kGreen),
            scaffoldBackgroundColor: kBg,
            fontFamily: 'Roboto',
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE0EAE3))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: kGreen, width: 1.5)),
            ),
          ),
          home: session.booting
              ? const SplashPage()
              : session.authenticated
                  ? MemberShell(session: session)
                  : LoginPage(session: session),
        );
      },
    );
  }
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        padding: EdgeInsets.all(size * 0.05),
        child: Image.asset('assets/app_sacco_logo.png', fit: BoxFit.contain),
      ),
    );
  }
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 112),
            SizedBox(height: 20),
            Text('APP SACCO', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kDarkGreen)),
            SizedBox(height: 8),
            Text('Save Together. Grow Together.', style: TextStyle(color: Color(0xFF66756C))),
            SizedBox(height: 28),
            CircularProgressIndicator(color: kGreen),
          ],
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.session});
  final SessionController session;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final login = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool obscure = true;
  String? error;

  @override
  void dispose() {
    login.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (login.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter your email/username and password.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.session.login(login.text, password.text);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  const AppLogo(size: 104),
                  const SizedBox(height: 16),
                  const Text('APP SACCO', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kDarkGreen)),
                  const SizedBox(height: 6),
                  const Text('Member App', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kGreen)),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 22, offset: Offset(0, 8))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Welcome back', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kDarkGreen)),
                        const SizedBox(height: 6),
                        const Text('Sign in to your SACCO account.', style: TextStyle(color: Color(0xFF6E7A72))),
                        const SizedBox(height: 20),
                        TextField(
                          controller: login,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: 'Email or username', prefixIcon: Icon(Icons.person_outline_rounded)),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: password,
                          obscureText: obscure,
                          onSubmitted: (_) => submit(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => obscure = !obscure),
                              icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            ),
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: const Color(0xFFFFEEEE), borderRadius: BorderRadius.circular(12)),
                            child: Text(error!, style: const TextStyle(color: Color(0xFFA62323), fontWeight: FontWeight.w600)),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: busy ? null : submit,
                          style: FilledButton.styleFrom(backgroundColor: kGreen, padding: const EdgeInsets.symmetric(vertical: 16)),
                          child: busy
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('Secure access to savings, shares, loans and statements.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF718077))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MemberShell extends StatefulWidget {
  const MemberShell({super.key, required this.session});
  final SessionController session;

  @override
  State<MemberShell> createState() => _MemberShellState();
}

class _MemberShellState extends State<MemberShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DashboardPage(session: widget.session),
      AccountsPage(session: widget.session),
      LoansPage(session: widget.session),
      ActivityPage(session: widget.session),
      MorePage(session: widget.session),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.account_balance_outlined), selectedIcon: Icon(Icons.account_balance_rounded), label: 'Savings'),
          NavigationDestination(icon: Icon(Icons.request_quote_outlined), selectedIcon: Icon(Icons.request_quote_rounded), label: 'Loans'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), selectedIcon: Icon(Icons.grid_view_rounded), label: 'More'),
        ],
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, required this.subtitle, this.trailing});
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [kDarkGreen, kGreen], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
      ),
      child: Row(
        children: [
          const AppLogo(size: 54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFDFF3E7), fontSize: 12.5)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.session});
  final SessionController session;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool loading = true;
  String? error;
  Map<String, dynamic> data = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.session.api.get('/member/dashboard');
      if (mounted) setState(() => data = mapOf(result['data']));
      await widget.session.refreshIdentity();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = mapOf(data['member']).isNotEmpty ? mapOf(data['member']) : widget.session.member;
    final compulsory = numOf(member['compulsory_savings_balance']);
    final voluntary = numOf(member['voluntary_savings_balance']);
    final shares = numOf(member['share_balance']);
    final loans = numOf(member['loan_balance']);
    final totalSavings = compulsory + voluntary;
    final net = totalSavings + shares - loans;
    final tx = listOf(data['recent_transactions']);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          PageHeader(
            title: 'Hello, ${widget.session.name.split(' ').first}',
            subtitle: '${widget.session.memberNo}  •  Track your SACCO position anywhere.',
            trailing: IconButton(
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            ),
          ),
          Expanded(
            child: loading && data.isEmpty
                ? const Center(child: CircularProgressIndicator(color: kGreen))
                : error != null && data.isEmpty
                    ? ErrorPane(message: error!, retry: load)
                    : RefreshIndicator(
                        onRefresh: load,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                          children: [
                            GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 1.55,
                              children: [
                                SummaryCard(label: 'Total Savings', value: money(totalSavings, widget.session.currency), icon: Icons.savings_rounded),
                                SummaryCard(label: 'Shares', value: money(shares, widget.session.currency), icon: Icons.pie_chart_rounded),
                                SummaryCard(label: 'Loan Outstanding', value: money(loans, widget.session.currency), icon: Icons.request_quote_rounded),
                                SummaryCard(label: 'Net Position', value: money(net, widget.session.currency), icon: Icons.trending_up_rounded, highlight: true),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: StatusChip(icon: Icons.pending_actions_rounded, label: 'Pending loans', value: textOf(data['pending_loans'], '0'))),
                                const SizedBox(width: 10),
                                Expanded(child: StatusChip(icon: Icons.notifications_active_rounded, label: 'Unread alerts', value: textOf(data['unread_notifications'], '0'))),
                              ],
                            ),
                            const SizedBox(height: 18),
                            const SectionTitle(title: 'Quick Actions'),
                            const SizedBox(height: 10),
                            GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 2.25,
                              children: [
                                ActionTile(icon: Icons.picture_as_pdf_rounded, title: 'Statement', subtitle: 'Share PDF', onTap: () => PdfService.shareStatement(widget.session, context)),
                                ActionTile(icon: Icons.receipt_long_rounded, title: 'Receipts', subtitle: 'Transaction PDFs', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityPage(session: widget.session, standalone: true)))),
                                ActionTile(icon: Icons.credit_score_rounded, title: 'Loans', subtitle: 'Apply & track', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoansPage(session: widget.session, standalone: true)))),
                                ActionTile(icon: Icons.person_rounded, title: 'Profile', subtitle: 'Member details', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(session: widget.session)))),
                              ],
                            ),
                            const SizedBox(height: 20),
                            const SectionTitle(title: 'Recent Activity'),
                            const SizedBox(height: 8),
                            if (tx.isEmpty)
                              const EmptyCard(text: 'No recent transactions yet.')
                            else
                              ...tx.take(6).map((item) => TransactionCard(item: mapOf(item), currency: widget.session.currency)),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.label, required this.value, required this.icon, this.highlight = false});
  final String label;
  final String value;
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFE5F6EB) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4ECE6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [Icon(icon, size: 20, color: kGreen), const SizedBox(width: 7), Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF718077), fontWeight: FontWeight.w600)))]),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, color: kDarkGreen, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE4ECE6))),
      child: Row(children: [Icon(icon, color: kGreen), const SizedBox(width: 8), Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))), Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: kDarkGreen))]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kDarkGreen))), if (action != null) action!]);
}

class ActionTile extends StatelessWidget {
  const ActionTile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE4ECE6))),
          child: Row(children: [Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFFE9F7EE), borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: kGreen, size: 20)), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(title, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)), Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: Color(0xFF778078)))]))]),
        ),
      ),
    );
  }
}

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key, required this.session, this.standalone = false});
  final SessionController session;
  final bool standalone;
  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  bool loading = true;
  String? error;
  List<dynamic> accounts = <dynamic>[];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await widget.session.api.get('/member/accounts');
      if (mounted) setState(() => accounts = listOf(mapOf(result['data'])['accounts']));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(children: [
      PageHeader(title: 'Savings & Shares', subtitle: '${widget.session.memberNo}  •  Your member accounts'),
      Expanded(child: loading ? const Center(child: CircularProgressIndicator(color: kGreen)) : error != null ? ErrorPane(message: error!, retry: load) : RefreshIndicator(onRefresh: load, child: accounts.isEmpty ? const ListView(children: [SizedBox(height: 180), EmptyPane(icon: Icons.account_balance_wallet_outlined, text: 'No member accounts found.')]) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: accounts.length, itemBuilder: (_, i) { final a = mapOf(accounts[i]); return AccountCard(account: a, currency: widget.session.currency); }))),
    ]);
    return widget.standalone ? Scaffold(appBar: AppBar(title: const Text('Savings & Shares')), body: SafeArea(top: false, child: body)) : SafeArea(bottom: false, child: body);
  }
}

class AccountCard extends StatelessWidget {
  const AccountCard({super.key, required this.account, required this.currency});
  final Map<String, dynamic> account;
  final String currency;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE2EBE5))),
      child: Row(children: [
        Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFFE5F6EB), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.savings_rounded, color: kGreen)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(pretty(account['account_type']), style: const TextStyle(fontWeight: FontWeight.w900, color: kDarkGreen)), const SizedBox(height: 4), Text(textOf(account['account_number'], 'Member account'), style: const TextStyle(color: Color(0xFF718077), fontSize: 12)), const SizedBox(height: 3), Text(pretty(account['status']), style: const TextStyle(color: kGreen, fontSize: 11, fontWeight: FontWeight.w700))])),
        Text(money(account['balance'], currency), style: const TextStyle(fontWeight: FontWeight.w900, color: kDarkGreen)),
      ]),
    );
  }
}

class LoansPage extends StatefulWidget {
  const LoansPage({super.key, required this.session, this.standalone = false});
  final SessionController session;
  final bool standalone;
  @override
  State<LoansPage> createState() => _LoansPageState();
}

class _LoansPageState extends State<LoansPage> {
  bool loading = true;
  String? error;
  Map<String, dynamic> data = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await widget.session.api.get('/member/loans');
      if (mounted) setState(() => data = mapOf(result['data']));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> apply() async {
    final products = listOf(data['products']);
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active loan products are available.')));
      return;
    }
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => LoanApplicationPage(session: widget.session, products: products)));
    if (changed == true) load();
  }

  @override
  Widget build(BuildContext context) {
    final active = listOf(data['active_loans']);
    final applications = listOf(data['applications']);
    final content = Column(children: [
      PageHeader(title: 'Loan Centre', subtitle: 'Apply, track and review your SACCO loans', trailing: IconButton(onPressed: loading ? null : apply, icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white))),
      Expanded(child: loading ? const Center(child: CircularProgressIndicator(color: kGreen)) : error != null ? ErrorPane(message: error!, retry: load) : RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(16), children: [
        FilledButton.icon(onPressed: apply, icon: const Icon(Icons.add_rounded), label: const Text('Apply for a Loan'), style: FilledButton.styleFrom(backgroundColor: kGreen, padding: const EdgeInsets.symmetric(vertical: 14))),
        const SizedBox(height: 18),
        const SectionTitle(title: 'Active Loans'),
        const SizedBox(height: 8),
        if (active.isEmpty) const EmptyCard(text: 'No active loans.') else ...active.map((item) => LoanCard(loan: mapOf(item), currency: widget.session.currency)),
        const SizedBox(height: 18),
        const SectionTitle(title: 'Applications'),
        const SizedBox(height: 8),
        if (applications.isEmpty) const EmptyCard(text: 'No loan applications yet.') else ...applications.map((item) => LoanCard(loan: mapOf(item), currency: widget.session.currency, application: true)),
      ]))),
    ]);
    return widget.standalone ? Scaffold(appBar: AppBar(title: const Text('Loan Centre')), body: SafeArea(top: false, child: content)) : SafeArea(bottom: false, child: content);
  }
}

class LoanCard extends StatelessWidget {
  const LoanCard({super.key, required this.loan, required this.currency, this.application = false});
  final Map<String, dynamic> loan;
  final String currency;
  final bool application;
  @override
  Widget build(BuildContext context) {
    final amount = loan['outstanding_balance'] ?? loan['loan_balance'] ?? loan['approved_amount'] ?? loan['requested_amount'] ?? loan['principal_amount'] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE2EBE5))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFEAF7EE), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.request_quote_rounded, color: kGreen)),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(textOf(loan['product_name'], application ? 'Loan application' : 'SACCO Loan'), style: const TextStyle(fontWeight: FontWeight.w900, color: kDarkGreen)), const SizedBox(height: 4), Text(textOf(loan['reference'], 'Loan #${textOf(loan['id'])}'), style: const TextStyle(fontSize: 12, color: Color(0xFF718077))), const SizedBox(height: 6), Wrap(spacing: 6, runSpacing: 6, children: [SmallBadge(text: pretty(loan['status'])), if (textOf(loan['term_months']).isNotEmpty) SmallBadge(text: '${textOf(loan['term_months'])} months')])])),
        Text(money(amount, currency), style: const TextStyle(fontWeight: FontWeight.w900, color: kDarkGreen)),
      ]),
    );
  }
}

class SmallBadge extends StatelessWidget {
  const SmallBadge({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFEAF7EE), borderRadius: BorderRadius.circular(20)), child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kGreen)));
}

class LoanApplicationPage extends StatefulWidget {
  const LoanApplicationPage({super.key, required this.session, required this.products});
  final SessionController session;
  final List<dynamic> products;
  @override
  State<LoanApplicationPage> createState() => _LoanApplicationPageState();
}

class _LoanApplicationPageState extends State<LoanApplicationPage> {
  int? productId;
  final amount = TextEditingController();
  final term = TextEditingController();
  final purpose = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    amount.dispose(); term.dispose(); purpose.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (productId == null || numOf(amount.text) <= 0 || int.tryParse(term.text) == null) {
      setState(() => error = 'Select a product and enter a valid amount and term.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final result = await widget.session.api.post('/member/loans', body: {
        'loan_product_id': productId,
        'requested_amount': numOf(amount.text),
        'term_months': int.parse(term.text),
        'purpose': purpose.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(textOf(result['message'], 'Loan application submitted.'))));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Loan Application')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('Choose a SACCO loan product and enter the amount you need.', style: TextStyle(color: Color(0xFF66756C))),
          const SizedBox(height: 18),
          DropdownButtonFormField<int>(
            value: productId,
            decoration: const InputDecoration(labelText: 'Loan product', prefixIcon: Icon(Icons.category_outlined)),
            items: widget.products.map((item) { final p = mapOf(item); final id = int.tryParse(textOf(p['id'])) ?? 0; return DropdownMenuItem<int>(value: id, child: Text(textOf(p['name'], 'Loan Product'))); }).toList(),
            onChanged: (value) => setState(() => productId = value),
          ),
          const SizedBox(height: 14),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Requested amount (${widget.session.currency})', prefixIcon: const Icon(Icons.payments_outlined))),
          const SizedBox(height: 14),
          TextField(controller: term, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Term (months)', prefixIcon: Icon(Icons.calendar_month_outlined))),
          const SizedBox(height: 14),
          TextField(controller: purpose, maxLines: 4, decoration: const InputDecoration(labelText: 'Purpose', alignLabelWithHint: true, prefixIcon: Icon(Icons.description_outlined))),
          if (error != null) ...[const SizedBox(height: 12), Text(error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600))],
          const SizedBox(height: 20),
          FilledButton(onPressed: busy ? null : submit, style: FilledButton.styleFrom(backgroundColor: kGreen, padding: const EdgeInsets.symmetric(vertical: 15)), child: busy ? const CircularProgressIndicator(color: Colors.white) : const Text('Submit Application')),
        ],
      ),
    );
  }
}

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key, required this.session, this.standalone = false});
  final SessionController session;
  final bool standalone;
  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  bool loading = true;
  String? error;
  List<dynamic> items = <dynamic>[];
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final q = search.text.trim();
      final result = await widget.session.api.get('/member/transactions', query: q.isEmpty ? null : {'q': q});
      if (mounted) setState(() => items = listOf(mapOf(result['data'])['transactions']));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(children: [
      PageHeader(title: 'Activity & Receipts', subtitle: 'Search transactions and share native PDF receipts', trailing: IconButton(onPressed: () => PdfService.shareStatement(widget.session, context), icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white))),
      Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: TextField(controller: search, onSubmitted: (_) => load(), decoration: InputDecoration(hintText: 'Search reference or transaction', prefixIcon: const Icon(Icons.search_rounded), suffixIcon: IconButton(onPressed: load, icon: const Icon(Icons.arrow_forward_rounded))))),
      Expanded(child: loading ? const Center(child: CircularProgressIndicator(color: kGreen)) : error != null ? ErrorPane(message: error!, retry: load) : RefreshIndicator(onRefresh: load, child: items.isEmpty ? const ListView(children: [SizedBox(height: 180), EmptyPane(icon: Icons.receipt_long_outlined, text: 'No transactions found.')]) : ListView.builder(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), itemCount: items.length, itemBuilder: (_, i) { final t = mapOf(items[i]); return TransactionCard(item: t, currency: widget.session.currency, onReceipt: () => PdfService.shareReceipt(widget.session, t, context)); }))),
    ]);
    return widget.standalone ? Scaffold(appBar: AppBar(title: const Text('Activity & Receipts')), body: SafeArea(top: false, child: content)) : SafeArea(bottom: false, child: content);
  }
}

class TransactionCard extends StatelessWidget {
  const TransactionCard({super.key, required this.item, required this.currency, this.onReceipt});
  final Map<String, dynamic> item;
  final String currency;
  final VoidCallback? onReceipt;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE3ECE6))),
      child: Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFFE9F7EE), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.swap_horiz_rounded, color: kGreen)),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(pretty(item['transaction_type']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, color: kDarkGreen)), const SizedBox(height: 3), Text('${textOf(item['reference'], 'Transaction')}  •  ${dateText(item['transaction_date'] ?? item['created_at'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF718077)))])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(money(item['amount'], currency), style: const TextStyle(fontWeight: FontWeight.w900, color: kDarkGreen)), if (onReceipt != null) TextButton(onPressed: onReceipt, style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 28)), child: const Text('Receipt', style: TextStyle(fontSize: 11)))]),
      ]),
    );
  }
}

class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.session});
  final SessionController session;

  Future<void> logout(BuildContext context) async {
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Log out?'), content: const Text('You will need to sign in again to access APP SACCO.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log Out'))]));
    if (yes == true) await session.logout();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(children: [
        PageHeader(title: 'More Services', subtitle: '${session.name}  •  ${session.memberNo}'),
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          MoreTile(icon: Icons.person_outline_rounded, title: 'My Profile', subtitle: 'Member and contact information', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(session: session)))),
          MoreTile(icon: Icons.notifications_none_rounded, title: 'Notifications', subtitle: 'SACCO alerts and updates', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsPage(session: session)))),
          MoreTile(icon: Icons.picture_as_pdf_rounded, title: 'Statement PDF', subtitle: 'Generate and share your statement', onTap: () => PdfService.shareStatement(session, context)),
          MoreTile(icon: Icons.outbox_outlined, title: 'Withdrawal History', subtitle: 'View withdrawal requests', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WithdrawalsPage(session: session)))),
          MoreTile(icon: Icons.card_giftcard_outlined, title: 'Dividends', subtitle: 'View dividend history', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DividendsPage(session: session)))),
          const SizedBox(height: 8),
          MoreTile(icon: Icons.logout_rounded, title: 'Log Out', subtitle: 'Securely end this session', danger: true, onTap: () => logout(context)),
          const SizedBox(height: 14),
          const Center(child: Text('APP SACCO Native v2.0', style: TextStyle(fontSize: 11, color: Color(0xFF849087)))),
        ])),
      ]),
    );
  }
}

class MoreTile extends StatelessWidget {
  const MoreTile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap, this.danger = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 10), color: Colors.white, child: ListTile(onTap: onTap, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5), leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: danger ? const Color(0xFFFFECEC) : const Color(0xFFE9F7EE), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: danger ? Colors.red : kGreen)), title: Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: danger ? Colors.red.shade700 : kDarkGreen)), subtitle: Text(subtitle, style: const TextStyle(fontSize: 11.5)), trailing: const Icon(Icons.chevron_right_rounded)));
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.session});
  final SessionController session;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool loading = true;
  String? error;
  Map<String, dynamic> profile = <String, dynamic>{};
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try { final r = await widget.session.api.get('/member/profile'); if (mounted) setState(() => profile = mapOf(mapOf(r['data'])['profile'])); }
    catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => loading = false); }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('My Profile')), body: loading ? const Center(child: CircularProgressIndicator(color: kGreen)) : error != null ? ErrorPane(message: error!, retry: load) : ListView(padding: const EdgeInsets.all(18), children: [
      const Center(child: AppLogo(size: 92)), const SizedBox(height: 10), Center(child: Text(textOf(profile['member_name'], widget.session.name), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kDarkGreen))), Center(child: Text(textOf(profile['member_no'], widget.session.memberNo), style: const TextStyle(color: Color(0xFF718077)))), const SizedBox(height: 20),
      ProfileRow(icon: Icons.badge_outlined, label: 'Member Number', value: textOf(profile['member_no'], '-')),
      ProfileRow(icon: Icons.verified_outlined, label: 'Membership Status', value: pretty(profile['membership_status'] ?? profile['status'])),
      ProfileRow(icon: Icons.email_outlined, label: 'Email', value: textOf(profile['email'], '-')),
      ProfileRow(icon: Icons.phone_outlined, label: 'Phone', value: textOf(profile['mobile'] ?? profile['phone'], '-')),
      ProfileRow(icon: Icons.location_on_outlined, label: 'Address', value: textOf(profile['client_address'] ?? profile['client_city'], '-')),
      ProfileRow(icon: Icons.business_outlined, label: 'Employer', value: textOf(profile['client_employer'] ?? profile['employer_name'], '-')),
      ProfileRow(icon: Icons.calendar_month_outlined, label: 'Joined', value: dateText(profile['join_date'] ?? profile['created_at'])),
    ]));
  }
}

class ProfileRow extends StatelessWidget {
  const ProfileRow({super.key, required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 9), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE3ECE6))), child: Row(children: [Icon(icon, color: kGreen), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF718077))), const SizedBox(height: 2), Text(value, style: const TextStyle(fontWeight: FontWeight.w800, color: kDarkGreen))]))]));
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.session});
  final SessionController session;
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool loading = true;
  String? error;
  List<dynamic> items = <dynamic>[];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try { final r = await widget.session.api.get('/member/notifications'); if (mounted) setState(() => items = listOf(mapOf(r['data'])['notifications'])); }
    catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> markRead(Map<String, dynamic> item) async {
    final id = int.tryParse(textOf(item['id']));
    if (id == null) return;
    try { await widget.session.api.post('/member/notifications/$id/read'); await load(); } catch (_) {}
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Notifications')), body: loading ? const Center(child: CircularProgressIndicator(color: kGreen)) : error != null ? ErrorPane(message: error!, retry: load) : RefreshIndicator(onRefresh: load, child: items.isEmpty ? const ListView(children: [SizedBox(height: 180), EmptyPane(icon: Icons.notifications_none_rounded, text: 'No notifications yet.')]) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: items.length, itemBuilder: (_, i) { final n = mapOf(items[i]); final unread = n['read_at'] == null || textOf(n['read_at']).isEmpty; return Card(margin: const EdgeInsets.only(bottom: 9), color: unread ? const Color(0xFFF0FAF3) : Colors.white, child: ListTile(onTap: () => markRead(n), leading: Icon(unread ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, color: kGreen), title: Text(textOf(n['title'], 'APP SACCO Notification'), style: TextStyle(fontWeight: unread ? FontWeight.w900 : FontWeight.w700)), subtitle: Text('${textOf(n['message'])}\n${dateText(n['created_at'])}', maxLines: 4, overflow: TextOverflow.ellipsis), isThreeLine: true)); })));
}

class WithdrawalsPage extends StatefulWidget {
  const WithdrawalsPage({super.key, required this.session});
  final SessionController session;
  @override
  State<WithdrawalsPage> createState() => _WithdrawalsPageState();
}

class _WithdrawalsPageState extends State<WithdrawalsPage> {
  bool loading = true;
  String? error;
  List<dynamic> items = <dynamic>[];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try { final r = await widget.session.api.get('/member/withdrawals'); if (mounted) setState(() => items = listOf(mapOf(r['data'])['withdrawals'])); }
    catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => loading = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Withdrawal History')), body: loading ? const Center(child: CircularProgressIndicator(color: kGreen)) : error != null ? ErrorPane(message: error!, retry: load) : RefreshIndicator(onRefresh: load, child: items.isEmpty ? const ListView(children: [SizedBox(height: 180), EmptyPane(icon: Icons.outbox_outlined, text: 'No withdrawal records yet.')]) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: items.length, itemBuilder: (_, i) { final w = mapOf(items[i]); return InfoCard(icon: Icons.outbox_rounded, title: 'Withdrawal - ${pretty(w['status'])}', subtitle: '${textOf(w['account_number'], 'Member account')}  •  ${dateText(w['request_date'] ?? w['created_at'])}', value: money(w['amount'], widget.session.currency)); })));
}

class DividendsPage extends StatefulWidget {
  const DividendsPage({super.key, required this.session});
  final SessionController session;
  @override
  State<DividendsPage> createState() => _DividendsPageState();
}

class _DividendsPageState extends State<DividendsPage> {
  bool loading = true;
  String? error;
  List<dynamic> items = <dynamic>[];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try { final r = await widget.session.api.get('/member/dividends'); if (mounted) setState(() => items = listOf(mapOf(r['data'])['dividends'])); }
    catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => loading = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Dividends')), body: loading ? const Center(child: CircularProgressIndicator(color: kGreen)) : error != null ? ErrorPane(message: error!, retry: load) : RefreshIndicator(onRefresh: load, child: items.isEmpty ? const ListView(children: [SizedBox(height: 180), EmptyPane(icon: Icons.card_giftcard_outlined, text: 'No dividend records yet.')]) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: items.length, itemBuilder: (_, i) { final d = mapOf(items[i]); final amount = d['net_amount'] ?? d['amount'] ?? d['dividend_amount'] ?? 0; return InfoCard(icon: Icons.card_giftcard_rounded, title: textOf(d['period_name'] ?? d['year'], 'Dividend'), subtitle: '${pretty(d['status'])}  •  ${dateText(d['created_at'] ?? d['posted_at'])}', value: money(amount, widget.session.currency)); })));
}

class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.icon, required this.title, required this.subtitle, required this.value});
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE3ECE6))), child: Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFFEAF7EE), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: kGreen)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: kDarkGreen)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(fontSize: 11.5, color: Color(0xFF718077)))])), Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: kDarkGreen))]));
}

class ErrorPane extends StatelessWidget {
  const ErrorPane({super.key, required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off_rounded, size: 56, color: kGreen), const SizedBox(height: 12), const Text('Unable to load this screen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kDarkGreen)), const SizedBox(height: 8), Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF68766D))), const SizedBox(height: 18), FilledButton.icon(onPressed: retry, icon: const Icon(Icons.refresh_rounded), label: const Text('Try Again'))])));
}

class EmptyPane extends StatelessWidget {
  const EmptyPane({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 50, color: const Color(0xFF8AAC98)), const SizedBox(height: 10), Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF718077), fontWeight: FontWeight.w600))])));
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE3ECE6))), child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF718077))));
}

class PdfService {
  static Future<List<dynamic>> _transactions(SessionController session) async {
    final result = await session.api.get('/member/statement');
    return listOf(mapOf(result['data'])['transactions']);
  }

  static Future<void> shareStatement(SessionController session, BuildContext context) async {
    try {
      final transactions = await _transactions(session);
      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (pdfContext) => [
            pw.Text('APP SACCO', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Member Statement', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text('${session.name} - ${session.memberNo}'),
            pw.Text('Generated: ${DateFormat('dd MMM yyyy HH:mm').format(DateTime.now())}'),
            pw.SizedBox(height: 18),
            if (transactions.isEmpty)
              pw.Text('No transactions found.')
            else
              pw.TableHelper.fromTextArray(
                headers: const ['Date', 'Type', 'Reference', 'Amount'],
                data: transactions.map((item) {
                  final t = mapOf(item);
                  return [dateText(t['transaction_date'] ?? t['created_at']), pretty(t['transaction_type']), textOf(t['reference'], '-'), money(t['amount'], session.currency)];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.green100),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellPadding: const pw.EdgeInsets.all(5),
              ),
            pw.SizedBox(height: 18),
            pw.Text('Generated by APP SACCO Native Mobile', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ],
        ),
      );
      await Printing.sharePdf(bytes: await doc.save(), filename: 'APP_SACCO_Statement_${session.memberNo}.pdf');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  static Future<void> shareReceipt(SessionController session, Map<String, dynamic> transaction, BuildContext context) async {
    try {
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          margin: const pw.EdgeInsets.all(26),
          build: (pdfContext) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('APP SACCO', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.Text('Transaction Receipt', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              _pdfRow('Member', session.name),
              _pdfRow('Member No.', session.memberNo),
              _pdfRow('Reference', textOf(transaction['reference'], '-')),
              _pdfRow('Transaction', pretty(transaction['transaction_type'])),
              _pdfRow('Date', dateText(transaction['transaction_date'] ?? transaction['created_at'])),
              _pdfRow('Account', textOf(transaction['account_number'], '-')),
              _pdfRow('Amount', money(transaction['amount'], session.currency)),
              if (textOf(transaction['notes']).isNotEmpty) _pdfRow('Notes', textOf(transaction['notes'])),
              pw.SizedBox(height: 20),
              pw.Text('This receipt was generated securely by APP SACCO Native Mobile.', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            ],
          ),
        ),
      );
      final ref = textOf(transaction['reference'], textOf(transaction['id'], 'receipt')).replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      await Printing.sharePdf(bytes: await doc.save(), filename: 'APP_SACCO_Receipt_$ref.pdf');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  static pw.Widget _pdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(children: [pw.SizedBox(width: 95, child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))), pw.Expanded(child: pw.Text(value))]),
    );
  }
}
