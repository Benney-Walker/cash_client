import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/glass_card.dart';
import '../common/glass_label.dart';
import '../common/gradient_button.dart';
import '../common/gradient_wash.dart';
import '../settings/app_info.dart';
import '../theme/app_gradients.dart';
import '../theme/app_status_colors.dart';
import 'session_manager.dart';
import 'shield_illustration.dart';
import 'sign_in.dart';

/// Sign-in, design option 2 ("glass card"): the pale gradient wash fills
/// the screen, with the shield and app name at the top and the form in a
/// frosted card.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.sessions, required this.appInfo});

  /// Signing in through this updates the session, which takes the app past
  /// this screen.
  final SessionManager sessions;

  /// For the version line in the corner.
  final AppInfo appInfo;

  /// Colour for a field's validation message, which sits on the glass card
  /// rather than on a solid surface. In dark mode no red is readable there
  /// (where the card crosses the teal glow, even the palest error tone is
  /// about 3.4:1), so the message uses the card's white text; the field's
  /// red border still marks the error. Checked in the contrast tests.
  static Color fieldErrorColor(ThemeData theme) =>
      theme.brightness == Brightness.dark
          ? theme.extension<AppGradients>()!.panelText
          : theme.colorScheme.error;

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
      await widget.sessions.signIn(
        // Staff IDs never contain spaces, so trailing ones from the keyboard
        // are dropped. The password is sent exactly as typed.
        staffId: _staffIdController.text.trim(),
        password: _passwordController.text,
      );
      // Normally the app has already moved past this screen by now.
      if (mounted) setState(() => _submitting = false);
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
    final gradients = AppGradients.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    // The wash runs under the status bar, so its icons follow the wash:
    // dark icons on the pale light-mode wash, light icons on the dark one.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: GradientWash(
          child: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    children: [
                      const SizedBox(height: 24),
                      const ShieldIllustration(),
                      const SizedBox(height: 8),
                      Text(
                        'Cash Client',
                        style: textTheme.titleLarge?.copyWith(
                          color: gradients.panelText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Daily collections',
                        style: textTheme.bodyMedium?.copyWith(
                          color: gradients.panelTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: ConstrainedBox(
                          // Keeps the card a comfortable width on tablets.
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: GlassCard(child: _buildForm(context)),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Version ${widget.appInfo.versionLabel} · '
                            'Powered by Bynex Labs',
                            key: const Key('login.version'),
                            style: textTheme.bodySmall?.copyWith(
                              color: gradients.panelTextSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final gradients = AppGradients.of(context);
    final textTheme = theme.textTheme;
    final errorStyle = TextStyle(
      color: LoginScreen.fieldErrorColor(theme),
    );

    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sign in',
              style: textTheme.headlineSmall?.copyWith(
                color: gradients.panelText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            // The card uses the main panel text colour for everything: the
            // lighter secondary tone is below 4.5:1 on dark-mode glass.
            Text(
              'Use the staff ID and password the office gave you.',
              style: textTheme.bodyMedium?.copyWith(color: gradients.panelText),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('login.staffId'),
              controller: _staffIdController,
              enabled: !_submitting,
              // The label stays inside the field instead of floating up onto
              // the glass, where its colours would be too faint to read.
              decoration: InputDecoration(
                labelText: 'Staff ID',
                floatingLabelBehavior: FloatingLabelBehavior.never,
                prefixIcon: const Icon(Icons.badge_outlined),
                errorStyle: errorStyle,
              ),
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.username],
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Enter your staff ID'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('login.password'),
              controller: _passwordController,
              enabled: !_submitting,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                floatingLabelBehavior: FloatingLabelBehavior.never,
                prefixIcon: const Icon(Icons.lock_outline),
                errorStyle: errorStyle,
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _submit(),
              validator: (value) =>
                  (value == null || value.isEmpty) ? 'Enter your password' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _Banner.error(message: _error!),
            ] else if (widget.sessions.sessionEndedByServer) ...[
              const SizedBox(height: 16),
              const _Banner.notice(
                message: 'Your session has ended. Sign in again to continue.',
              ),
            ],
            const SizedBox(height: 20),
            GradientButton(
              key: const Key('login.submit'),
              // Stays enabled while signing in so the spinner sits on the
              // full-strength gradient; _submit ignores repeat taps instead.
              onPressed: _submit,
              child: _submitting
                  ? SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: gradients.onButton,
                        semanticsLabel: 'Signing in',
                      ),
                    )
                  : const Text('Sign in'),
            ),
            const SizedBox(height: 16),
            const Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                GlassLabel(icon: Icons.groups_outlined, label: 'Collectors only'),
                GlassLabel(icon: Icons.lock_outline, label: 'Protected'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A message above the button: an error after a failed sign-in, or a notice
/// when the backend ended the session. Solid tints, so they read the same on
/// any part of the wash.
class _Banner extends StatelessWidget {
  const _Banner.error({required this.message}) : _isError = true;
  const _Banner.notice({required this.message}) : _isError = false;

  final String message;
  final bool _isError;

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final foreground = _isError ? status.danger : status.warning;
    final background =
        _isError ? status.dangerContainer : status.warningContainer;

    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _isError ? Icons.error_outline : Icons.info_outline,
                color: foreground,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  key: Key(_isError ? 'login.error' : 'login.notice'),
                  style: TextStyle(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
