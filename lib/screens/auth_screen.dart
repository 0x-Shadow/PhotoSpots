import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../state/auth_state.dart';
import '../theme/app_animations.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/validators.dart';
import '../widgets/glass.dart';

/// Email + password account entry, in the same photo-and-glass language as the
/// welcome screen: a full-bleed image, a dark scrim, and one frosted card that
/// holds the whole form.
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

  void _switchMode({bool? signUp}) {
    final next = signUp ?? !_signUp;
    if (next == _signUp) return;
    setState(() {
      _signUp = next;
      _formError = null;
    });
    _formKey.currentState?.reset();
  }

  Future<void> _resetPassword() async {
    final controller = TextEditingController(text: _email.text.trim());
    final submitted = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset password'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Account email',
            hintText: 'you@example.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (submitted == null || !mounted) return;
    final res = await context.read<AuthState>().sendPasswordReset(submitted);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res.message ?? 'Check your inbox.')),
    );
  }

  InputDecoration _field(String label, {String? hint, Widget? suffix}) {
    const radius = BorderRadius.all(Radius.circular(14));
    const border = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: Color(0x24FFFFFF)),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13.5,
      ),
      floatingLabelStyle: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12.5,
      ),
      filled: true,
      fillColor: const Color(0x0FFFFFFF),
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border,
      enabledBorder: border,
      focusedBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: Color(0x66FFFFFF)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/splash_hero.jpg',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1C2733), Color(0xFF08090B)],
                ),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66000000),
                  Color(0x33000000),
                  Color(0xF20A0A0B),
                ],
                stops: [0.0, 0.42, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight > 32
                          ? constraints.maxHeight - 32
                          : 0,
                    ),
                    child: ResponsiveBody(
                      maxWidth: 440,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              GlassIconButton(
                                icon: Icons.close_rounded,
                                semanticLabel: 'Close',
                                onTap: () =>
                                    Navigator.of(context).maybePop(),
                              ),
                              const Spacer(),
                              const Text(
                                'photospot.',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.7,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 44),
                          Text(
                            _signUp ? 'Create your account' : 'Welcome back',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 31,
                              height: 1.08,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _signUp
                                ? 'Keep your saves, likes and comments on every '
                                      'device — and add your own spots to the map.'
                                : 'Sign in to sync your saves, likes and '
                                      'comments across every device.',
                            style: const TextStyle(
                              color: Color(0xCCFFFFFF),
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 22),
                          GlassPanel(
                            borderRadius: 28,
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _ModeSwitch(
                                  signUp: _signUp,
                                  onChanged: (value) =>
                                      _switchMode(signUp: value),
                                ),
                                const SizedBox(height: 18),
                                Form(
                                  key: _formKey,
                                  child: Column(
                                    children: [
                                      if (_signUp) ...[
                                        TextFormField(
                                          key: const ValueKey('auth_name'),
                                          controller: _name,
                                          textCapitalization:
                                              TextCapitalization.words,
                                          autofillHints: const [
                                            AutofillHints.name,
                                          ],
                                          validator: Validators.displayName,
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 15,
                                          ),
                                          decoration: _field(
                                            'Display name',
                                            hint: 'How you appear on spots',
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                      ],
                                      TextFormField(
                                        key: const ValueKey('auth_email'),
                                        controller: _email,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        autocorrect: false,
                                        autofillHints: const [
                                          AutofillHints.email,
                                        ],
                                        validator: Validators.email,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 15,
                                        ),
                                        decoration: _field(
                                          'Email',
                                          hint: 'you@example.com',
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
                                            ? const [
                                                AutofillHints.newPassword,
                                              ]
                                            : const [AutofillHints.password],
                                        validator: _signUp
                                            ? Validators.password
                                            : null,
                                        onFieldSubmitted: (_) => _submit(),
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 15,
                                        ),
                                        decoration: _field(
                                          'Password',
                                          hint: _signUp
                                              ? '8+ characters, letters and numbers'
                                              : 'Your password',
                                          suffix: IconButton(
                                            tooltip: _obscure
                                                ? 'Show password'
                                                : 'Hide password',
                                            onPressed: () => setState(
                                              () => _obscure = !_obscure,
                                            ),
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
                                      color: AppColors.danger.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppColors.danger.withValues(
                                          alpha: 0.35,
                                        ),
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
                                  semanticLabel: _signUp
                                      ? 'Create account'
                                      : 'Sign in',
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
                                            _signUp
                                                ? 'Create account'
                                                : 'Sign in',
                                            style: const TextStyle(
                                              color: AppColors.onAction,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                  ),
                                ),
                                if (!_signUp &&
                                    AuthState.supportsAccounts) ...[
                                  const SizedBox(height: 4),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: auth.busy
                                          ? null
                                          : _resetPassword,
                                      style: TextButton.styleFrom(
                                        foregroundColor:
                                            AppColors.textSecondary,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      child: const Text('Forgot password?'),
                                    ),
                                  ),
                                ],
                                if (!AuthState.supportsAccounts) ...[
                                  const SizedBox(height: 14),
                                  const Text(
                                    'This build runs in demo mode, so accounts '
                                    'need the hosted backend. Your demo profile '
                                    'still works and nothing here is sent '
                                    'anywhere.',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Center(
                            child: TextButton(
                              onPressed: auth.busy
                                  ? null
                                  : () => _switchMode(),
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
                          Center(
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(context).maybePop(),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                              ),
                              child: const Text('Continue as guest'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Passwords go straight to the auth provider and '
                            'are never stored in the app. Row-level security '
                            'means only you can change your profile and '
                            'comments.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0x99FFFFFF),
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              '${AppInfo.name} · secure accounts',
                              style: const TextStyle(
                                color: Color(0x80FFFFFF),
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A two-option frosted segmented control for Sign in / Create account.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.signUp, required this.onChanged});

  final bool signUp;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeTab(
              label: 'Sign in',
              selected: !signUp,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _ModeTab(
              label: 'Create account',
              selected: signUp,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: PressButton(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.quick,
          curve: AppMotion.easeOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.action : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.onAction : AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
