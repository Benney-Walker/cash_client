import 'package:flutter/material.dart';

import '../theme/app_status_colors.dart';
import 'auth_session.dart';
import 'sign_in.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.signIn,
    required this.onSignedIn,
  });

  final SignIn signIn;
  final ValueChanged<AuthSession> onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _staffIdController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _staffIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      final session = await widget.signIn(
        // Staff IDs never contain spaces, so trailing ones from the keyboard
        // are dropped. The password is sent exactly as typed.
        staffId: _staffIdController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      widget.onSignedIn(session);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = signInErrorMessage(error);
      });
      // A failed attempt shouldn't leave the password sitting in the field.
      _passwordController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Header(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Sign in', style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 4),
                        Text(
                          'Use the staff ID and password the office gave you.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          key: const Key('login.staffId'),
                          controller: _staffIdController,
                          enabled: !_submitting,
                          decoration: const InputDecoration(
                            labelText: 'Staff ID',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.username],
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                                  ? 'Enter your staff ID'
                                  : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('login.password'),
                          controller: _passwordController,
                          enabled: !_submitting,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _submit(),
                          validator: (value) => (value == null || value.isEmpty)
                              ? 'Enter your password'
                              : null,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          _ErrorBanner(message: _error!),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          key: const Key('login.submit'),
                          // Stays enabled while signing in so the spinner
                          // sits on the primary colour; _submit ignores
                          // repeat taps instead.
                          onPressed: _submit,
                          child: _submitting
                              ? SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: scheme.onPrimary,
                                    semanticsLabel: 'Signing in',
                                  ),
                                )
                              : const Text('Sign in'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The login header is one of the few places the hero gradient is used.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final topInset = MediaQuery.paddingOf(context).top;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: status.heroGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, topInset + 40, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              color: status.onHero,
              size: 36,
            ),
            const SizedBox(height: 16),
            Text(
              'Cash Client',
              style: textTheme.headlineMedium?.copyWith(color: status.onHero),
            ),
            const SizedBox(height: 4),
            Text(
              'Daily collections',
              style: textTheme.bodyLarge
                  ?.copyWith(color: status.onHeroSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: status.dangerContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: status.danger, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  key: const Key('login.error'),
                  style: TextStyle(color: status.danger),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
