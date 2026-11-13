import 'package:flutter/material.dart';

import '../../../core/config/identity_config.dart';
import '../../../core/errors/identity_exception.dart';
import '../domain/identity_models.dart';
import 'identity_controller.dart';

String _safeError(Object error) => error is IdentityException
    ? error.message
    : 'The request could not be completed. Check your connection and try again.';

String _title(IdentityAppMode mode) => mode == IdentityAppMode.courier
    ? 'SwiftDrop Courier'
    : 'SwiftDrop Customer';

class IdentitySignInScreen extends StatefulWidget {
  const IdentitySignInScreen({
    super.key,
    required this.controller,
    required this.mode,
    required this.googleEnabled,
    this.initialNotice,
  });

  final IdentityController controller;
  final IdentityAppMode mode;
  final bool googleEnabled;
  final String? initialNotice;

  @override
  State<IdentitySignInScreen> createState() => _IdentitySignInScreenState();
}

class _IdentitySignInScreenState extends State<IdentitySignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _registering = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _notice = widget.initialNotice;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.controller.busy || !_form.currentState!.validate()) return;
    final password = _password.text;
    final email = _email.text.trim();
    final name = _name.text.trim();
    _password.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _error = null;
      _notice = null;
    });
    try {
      if (_registering) {
        await widget.controller.register(email, password, name);
        if (mounted) {
          setState(() {
            _registering = false;
            _name.clear();
            _notice = 'Your account was created. Sign in to continue.';
          });
          _form.currentState?.reset();
        }
      } else {
        await widget.controller.login(email, password);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _safeError(error));
    }
  }

  Future<void> _google() async {
    setState(() {
      _error = null;
      _notice = null;
    });
    try {
      final completed = await widget.controller.googleLogin();
      if (!completed && mounted) {
        setState(() => _notice = 'Google sign-in was cancelled.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = _safeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.controller.busy;
    return Scaffold(
      appBar: AppBar(title: Text(_title(widget.mode))),
      body: _Page(
        children: [
          Text(
            _registering ? 'Create your account' : 'Welcome back',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _registering
                ? 'New accounts start as Customers. Courier access requires an authorized Courier role.'
                : 'Sign in to manage your SwiftDrop profile.',
          ),
          const SizedBox(height: 24),
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_registering) ...[
                  TextFormField(
                    key: const Key('registration-name'),
                    controller: _name,
                    enabled: !busy,
                    maxLength: 120,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter your full name.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  key: const Key('sign-in-email'),
                  controller: _email,
                  enabled: !busy,
                  maxLength: 254,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    return !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                            .hasMatch(email)
                        ? 'Enter a valid email address.'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('sign-in-password'),
                  controller: _password,
                  enabled: !busy,
                  obscureText: true,
                  maxLength: 128,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: [
                    _registering
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Enter your password.';
                    }
                    if (_registering && value.length < 12) {
                      return 'Use at least 12 characters.';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('local-sign-in-submit'),
                  onPressed: busy ? null : _submit,
                  child: Text(
                    busy
                        ? 'Please wait…'
                        : _registering
                        ? 'Create account'
                        : 'Sign in',
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          _password.clear();
                          _form.currentState?.reset();
                          setState(() {
                            _registering = !_registering;
                            _error = null;
                            _notice = null;
                          });
                        },
                  child: Text(
                    _registering
                        ? 'Already registered? Sign in'
                        : 'Create a Customer account',
                  ),
                ),
              ],
            ),
          ),
          if (widget.googleEnabled) ...[
            const Divider(height: 32),
            OutlinedButton.icon(
              key: const Key('google-sign-in'),
              onPressed: busy ? null : _google,
              icon: const Icon(Icons.account_circle_outlined),
              label: const Text('Continue with Google'),
            ),
          ] else
            const Text('Google sign-in is unavailable for this deployment.'),
          if (busy) const LinearProgressIndicator(),
          _Feedback(error: _error, notice: _notice),
        ],
      ),
    );
  }
}

class IdentityProfileScreen extends StatefulWidget {
  const IdentityProfileScreen({
    super.key,
    required this.controller,
    required this.mode,
    required this.googleEnabled,
  });

  final IdentityController controller;
  final IdentityAppMode mode;
  final bool googleEnabled;

  @override
  State<IdentityProfileScreen> createState() => _IdentityProfileScreenState();
}

class _IdentityProfileScreenState extends State<IdentityProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _password = TextEditingController();
  String? _loadedUser;
  bool _working = false;
  String? _error;
  String? _notice;

  void _load(IdentityProfile user) {
    _loadedUser = user.id;
    _name.text = user.fullName;
    _phone.text = user.phoneNumber ?? '';
    _address.text = user.address ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (widget.controller.busy || _working || !_form.currentState!.validate()) {
      return;
    }
    await _perform(() async {
      await widget.controller.updateProfile(
        fullName: _name.text.trim(),
        phoneNumber: _phone.text.trim(),
        address: _address.text.trim(),
      );
      if (mounted && widget.controller.user != null) {
        _load(widget.controller.user!);
      }
      return 'Your profile was saved.';
    });
  }

  Future<void> _reload() => _perform(() async {
    await widget.controller.refreshProfile();
    if (mounted && widget.controller.user != null) {
      _load(widget.controller.user!);
    }
    return 'Your profile is up to date.';
  });

  Future<void> _link() async {
    if (_password.text.isEmpty || widget.controller.busy || _working) return;
    final password = _password.text;
    _password.clear();
    await _perform(() async {
      final completed = await widget.controller.linkGoogle(password);
      return completed
          ? 'Google was linked to your account.'
          : 'Google linking was cancelled.';
    });
  }

  Future<void> _perform(Future<String> Function() action) async {
    if (_working || widget.controller.busy) return;
    setState(() {
      _working = true;
      _error = null;
      _notice = null;
    });
    try {
      final notice = await action();
      if (mounted) setState(() => _notice = notice);
    } catch (error) {
      if (mounted) setState(() => _error = _safeError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _logout() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.controller.logout();
    } catch (error) {
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(_safeError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.controller.user;
    if (user == null) return const SizedBox.shrink();
    if (_loadedUser != user.id) _load(user);
    final busy = widget.controller.busy || _working;
    final courierMode = widget.mode == IdentityAppMode.courier;
    final requiredRole = courierMode ? 'Courier' : 'Customer';
    final hasRole = user.roles.contains(requiredRole);
    return Scaffold(
      appBar: AppBar(
        title: Text(_title(widget.mode)),
        actions: [
          TextButton(
            key: const Key('sign-out'),
            onPressed: busy ? null : _logout,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: _Page(
        children: [
          Text('My profile', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasRole
                        ? '$requiredRole role verified'
                        : '$requiredRole access unavailable',
                    key: const Key('role-access-status'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasRole
                        ? 'Your profile uses the roles assigned to your account.'
                        : courierMode
                        ? 'This account does not have an authorized Courier role. Contact an Admin to request access.'
                        : 'This account does not have a Customer role. You can still manage your own profile.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(user.email, key: const Key('profile-email')),
          const SizedBox(height: 8),
          Text(
            user.roles.isEmpty
                ? 'No application roles assigned'
                : 'Roles: ${user.roles.join(', ')}',
          ),
          const SizedBox(height: 20),
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('profile-full-name'),
                  controller: _name,
                  enabled: !busy,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  autofillHints: const [AutofillHints.name],
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter your full name.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('profile-phone'),
                  controller: _phone,
                  enabled: !busy,
                  maxLength: 32,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('profile-address'),
                  controller: _address,
                  enabled: !busy,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Address'),
                  autofillHints: const [AutofillHints.fullStreetAddress],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('save-profile'),
                  onPressed: busy ? null : _save,
                  child: const Text('Save profile'),
                ),
                TextButton.icon(
                  key: const Key('reload-profile'),
                  onPressed: busy ? null : _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload profile'),
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          Text('Link Google', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Use a Google account with the same verified email. Confirm your current local password to link it.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('link-current-password'),
            controller: _password,
            enabled: !busy && widget.googleEnabled,
            obscureText: true,
            maxLength: 128,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Current password'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('link-google'),
            onPressed: busy || !widget.googleEnabled || _password.text.isEmpty
                ? null
                : _link,
            child: const Text('Link Google'),
          ),
          if (!widget.googleEnabled)
            const Text('Google linking is unavailable for this deployment.'),
          if (busy) const LinearProgressIndicator(),
          _Feedback(error: _error, notice: _notice),
        ],
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ),
  );
}

class _Feedback extends StatelessWidget {
  const _Feedback({this.error, this.notice});
  final String? error;
  final String? notice;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (notice != null) Text(notice!),
        ],
      ),
    ),
  );
}
