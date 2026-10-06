import 'dart:convert';
import 'dart:io';

import 'package:verapass/verapass.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// "Demo Bank": how an app integrates face verification.
///
/// The app never holds an API key. It asks *its own server* (here the demo server in
/// web-sdk/demo/server.mjs) to start a verification; that server uses the API key to create
/// a session and returns a one-session client token. Afterwards the app asks its server to
/// confirm the result, because a result reported by the app itself can't be trusted.
void main() => runApp(const DemoBankApp());

class DemoBankApp extends StatefulWidget {
  const DemoBankApp({super.key});

  @override
  State<DemoBankApp> createState() => _DemoBankAppState();
}

class _DemoBankAppState extends State<DemoBankApp> {
  bool dark = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Demo Bank',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF14532D), brightness: Brightness.light),
    darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF14532D), brightness: Brightness.dark),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: HomePage(dark: dark, onDarkChanged: (v) => setState(() => dark = v)),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.dark, required this.onDarkChanged});
  final bool dark;
  final ValueChanged<bool> onDarkChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final apiUrl = TextEditingController(text: 'https://api.verapass.app');
  // The demo server runs on the developer's computer: the Android emulator reaches it at
  // 10.0.2.2, the iOS simulator at localhost; a real phone needs the computer's LAN address.
  final demoServer = TextEditingController(
    text: const String.fromEnvironment('DEMO_SERVER').isNotEmpty
        ? const String.fromEnvironment('DEMO_SERVER')
        : (Platform.isAndroid ? 'http://10.0.2.2:5181' : 'http://localhost:5181'),
  );
  String reference = 'uploaded';
  bool voice = true;
  bool instructions = true;
  String language = 'en';
  String? status;
  String? confirmed;
  bool busy = false;

  Future<String> _startOnMyServer() async {
    final response = await http.post(Uri.parse('${demoServer.text}/demo/session?reference=$reference')).timeout(const Duration(seconds: 30));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) throw Exception(body['detail'] ?? 'HTTP ${response.statusCode}');
    return body['clientToken'] as String;
  }

  Future<void> _verify() async {
    setState(() {
      busy = true;
      status = null;
      confirmed = null;
    });
    try {
      final result = await FaceVerification.start(
        context,
        apiUrl: Uri.parse(apiUrl.text),
        clientTokenProvider: _startOnMyServer,
        options: FaceVerificationOptions(voice: voice, instructions: instructions, language: language),
      );
      setState(() => status = 'App result: ${result.status.name}${result.failureCode == null ? '' : ' (${result.failureCode!.name})'}');
      // Never trust the app: ask our server, which asks the API with its key.
      final check = await http.get(Uri.parse('${demoServer.text}/demo/result/${result.sessionId}'));
      final server = jsonDecode(check.body) as Map<String, dynamic>;
      setState(() => confirmed = 'Server-confirmed: ${server['status']}${server['similarity'] == null ? '' : ', similarity ${(server['similarity'] as num).toStringAsFixed(2)}'}');
    } on FaceVerificationException catch (e) {
      setState(() => status = 'Not completed: ${e.code.name}');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Demo Bank')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Confirm it's you", style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('Before changing your payout details, we need to verify your identity.', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('verify'),
                    onPressed: busy ? null : _verify,
                    icon: const Icon(Icons.face),
                    label: const Text('Verify identity'),
                  ),
                  if (status != null) ...[const SizedBox(height: 16), Text(status!, key: const Key('status'))],
                  if (confirmed != null) ...[const SizedBox(height: 4), Text(confirmed!, key: const Key('confirmed'))],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ExpansionTile(
            title: const Text('Demo settings'),
            children: [
              TextField(controller: apiUrl, decoration: const InputDecoration(labelText: 'veraPass API URL')),
              TextField(controller: demoServer, decoration: const InputDecoration(labelText: 'Your server (demo server) URL')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: reference,
                decoration: const InputDecoration(labelText: 'Photo on file'),
                items: const [
                  DropdownMenuItem(value: 'uploaded', child: Text('The photo set on the demo server')),
                  DropdownMenuItem(value: 'bolden', child: Text("Test person (you won't match)")),
                ],
                onChanged: (v) => setState(() => reference = v!),
              ),
              SwitchListTile(title: const Text('Voice'), value: voice, onChanged: (v) => setState(() => voice = v)),
              SwitchListTile(title: const Text('Intro and on-screen hints'), value: instructions, onChanged: (v) => setState(() => instructions = v)),
              SwitchListTile(title: const Text('Dark theme'), value: widget.dark, onChanged: widget.onDarkChanged),
              DropdownButtonFormField<String>(
                initialValue: language,
                decoration: const InputDecoration(labelText: 'Language'),
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'es', child: Text('Español')),
                  DropdownMenuItem(value: 'fr', child: Text('Français')),
                ],
                onChanged: (v) => setState(() => language = v!),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
