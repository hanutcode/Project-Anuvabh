import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/phone_frame.dart';
import '../home/presentation/providers/home_provider.dart';
import '../shell/data/models/app_tab.dart';
import '../shell/presentation/providers/bottom_nav_provider.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool registering = false;
  bool visible = false;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    final home = context.read<HomeProvider>();
    final nav = context.read<BottomNavProvider>();
    final ok = await home.authenticate(registering, {
      'email': email.text.trim(),
      'password': password.text,
      if (registering) 'name': name.text.trim(),
    });
    if (ok) {
      password.clear();
      confirmation.clear();
      nav.select(AppTab.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    return Scaffold(
      body: PhoneFrame(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: AutofillGroup(
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: AppColors.lilac,
                          child: Icon(Icons.school_outlined, size: 28),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Project Anubhav',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        registering
                            ? 'Create your teaching space'
                            : 'Welcome back, Teacher',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        registering
                            ? 'Save your games, classes and classroom moments.'
                            : 'Log in to pick up where your classroom left off.',
                      ),
                      const SizedBox(height: 28),
                      if (registering) ...[
                        TextFormField(
                          controller: name,
                          enabled: !home.saving,
                          maxLength: 100,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(
                            labelText: 'Your name',
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter your name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: email,
                        enabled: !home.saving,
                        maxLength: 254,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                        validator: (value) =>
                            value == null ||
                                !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                    .hasMatch(value.trim())
                            ? 'Enter a valid email address'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: password,
                        enabled: !home.saving,
                        maxLength: registering ? 6 : 128,
                        keyboardType: registering
                            ? TextInputType.number
                            : TextInputType.visiblePassword,
                        inputFormatters: registering
                            ? [FilteringTextInputFormatter.digitsOnly]
                            : null,
                        obscureText: !visible,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: [
                          registering
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        onFieldSubmitted: (_) {
                          if (!registering && !home.saving) submit();
                        },
                        decoration: InputDecoration(
                          labelText: 'Password',
                          helperText: registering ? 'Exactly 6 digits' : null,
                          counterText: '',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: visible
                                ? 'Hide password'
                                : 'Show password',
                            onPressed: () => setState(() => visible = !visible),
                            icon: Icon(
                              visible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Enter your password'
                            : registering &&
                                  !RegExp(r'^[0-9]{6}$').hasMatch(value)
                            ? 'Enter exactly 6 digits'
                            : null,
                      ),
                      if (registering) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: confirmation,
                          enabled: !home.saving,
                          maxLength: 6,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          obscureText: !visible,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
                          validator: (value) => value != password.text
                              ? 'Passwords do not match'
                              : null,
                          onFieldSubmitted: (_) {
                            if (!home.saving) submit();
                          },
                        ),
                      ],
                      if (home.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            home.error!,
                            style: const TextStyle(
                              color: AppColors.destructive,
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: home.saving ? null : submit,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            home.saving
                                ? 'Please wait…'
                                : registering
                                ? 'Create account'
                                : 'Log in',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: home.saving
                            ? null
                            : () {
                                setState(() {
                                  registering = !registering;
                                  visible = false;
                                  password.clear();
                                  confirmation.clear();
                                  home.error = null;
                                  form.currentState?.reset();
                                });
                              },
                        child: Text(
                          registering
                              ? 'Already have an account? Log in'
                              : 'New here? Create an account',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
