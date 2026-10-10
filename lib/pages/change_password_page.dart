import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/password_policy.dart';
import '../widgets/app_logo.dart';

class ChangePasswordPage extends StatefulWidget {
  final String authId;
  const ChangePasswordPage({super.key, required this.authId});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final pw1 = TextEditingController();
  final pw2 = TextEditingController();
  bool loading = false;

  Future<void> _save() async {
    // Nessun trim silenzioso.
    final p1 = pw1.text;
    final p2 = pw2.text;

    if (p1.isEmpty || p2.isEmpty) {
      _toast("Compila tutti i campi");
      return;
    }
    if (p1 != p2) {
      _toast("Le password non coincidono");
      return;
    }
    final ruleError = PasswordPolicy.validate(
      p1,
      email: Supabase.instance.client.auth.currentUser?.email,
    );
    if (ruleError != null) {
      _toast(ruleError);
      return;
    }

    setState(() => loading = true);

    final sb = Supabase.instance.client;

    try {
      await sb.auth.updateUser(UserAttributes(password: p1));

      await sb
          .from("users")
          .update({'must_change_password': false})
          .eq("auth_id", widget.authId);

      final p = await sb
          .from("users")
          .select("*")
          .eq("auth_id", widget.authId)
          .maybeSingle();

      if (!mounted) return;

      final role = (p?["role"] ?? "").toString().toLowerCase();

      switch (role) {
        case "dipendente":
        case "user":
          Navigator.pushNamedAndRemoveUntil(
              context, "/dipendentePrenotazioni", (_) => false);
          break;

        case "caposquadra":
          Navigator.pushNamedAndRemoveUntil(
              context, "/caposquadraPrenotazioni", (_) => false);
          break;

        default:
          Navigator.pushNamedAndRemoveUntil(
            context,
            "/home",
            (_) => false,
            arguments: {
              "id": p?["id"],
              "username": p?["username"],
              "role": p?["role"],
              "secondary_role": p?["secondary_role"],
              "full_name": p?["full_name"],
              "email": p?["email"],
            },
          );
      }
    } catch (e) {
      _toast("Errore: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const ResponsiveAppBarTitle(title: "Cambia Password"),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: pw1,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Nuova password",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pw2,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Conferma password",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: loading ? null : _save,
                child: loading
                    ? const CircularProgressIndicator()
                    : const Text("Salva"),
              ),
            ],
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }
}