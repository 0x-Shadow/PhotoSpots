import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../state/auth_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/validators.dart';

/// Email + password account entry.
///
/// The password is handed to Supabase Auth and never stored by the app; the
/// session token is managed by the SDK. Errors are deliberately generic so the
/// form cannot be used to discover which emails have accounts.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.startInSignUp = false});

  final bool startInSignUp;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  late bool _signUp = widget.startInSignUp;
  bool _obscure = true;
  String? _formError;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _formError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthState>();
    final messenger = ScaffoldMessenger.of(context);

    final result = _signUp
        ? await auth.signUp(
            name: _name.text,
            email: _email.text,
            password: _password.text,
          )
        : await auth.signIn(email: _email.text, password: _password.text);

    if (!mounted) return;

    if (!result.success) {
      setState(() => _formError = result.message);
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text(result.message ?? 'Signed in.')),
    );

    // With email confirmation on, there is no session yet — stay so the user
    // sees the "check your inbox" message.
    if (auth.isSignedIn) {
      Navigator.of(context).maybePop();
    }
  }

  void _switchMode() {
    setState(() {
      _signUp = !_signUp;
      _formError = null;
    });
    _formKey.currentState?.reset();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: ResponsiveBody(
          maxWidth: 460,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.accent, Color(0xFF7C6CFF)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.3),
                      blurRadius: 24,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _signUp ? 'Create your account' : 'Welcome back',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _signUp
                    ? 'Keep your saves, likes and comments on every device.'
                    : 'Sign in to sync your saves, likes and comments.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              if (!AuthState.supportsAccounts) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: const Text(
                    'This build runs in demo mode, so accounts need the hosted '
                    'backend. Your demo profile still works and nothing here is '
                    'sent anywhere.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    if (_signUp) ...[
                      TextFormField(
                        key: const ValueKey('auth_name'),
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        validator: Validators.displayName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                          hintText: 'How you appear on spots',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      key: const ValueKey('auth_email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      validator: Validators.email,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'you@example.com',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('auth_password'),
                      controller: _password,
                      obscureText: _obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: _signUp
                          ? const [AutofillHints.newPassword]
                          : const [AutofillHints.password],
                      validator: _signUp ? Validators.password : null,
                      onFieldSubmitted: (_) => _submit(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: _signUp
                            ? '8+ characters, letters and numbers'
                            : 'Your password',
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: AppColors.textSecondary,
                            size: 19,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_formError != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    _formError!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              PressButton(
                semanticLabel: _signUp ? 'Create account' : 'Sign in',
                enabled: !auth.busy,
                onTap: _submit,
                child: Container(
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.action,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: auth.busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onAction,
                          ),
                        )
                      : Text(
                          _signUp ? 'Create account' : 'Sign in',
                          style: const TextStyle(
                            color: AppColors.onAction,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: auth.busy ? null : _switchMode,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                  ),
                  child: Text(
                    _signUp
                        ? 'I already have an account'
                        : 'Create a new account',
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                  child: const Text('Continue as guest'),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Passwords go straight to the auth provider and are never '
                'stored in the app. Your data is protected by row-level '
                'security, so only you can change your profile and comments.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  '${AppInfo.name} · secure accounts',
                  style: TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 10.5,
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
