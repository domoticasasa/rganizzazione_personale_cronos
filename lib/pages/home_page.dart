import 'package:flutter/material.dart';

import '../utils/roles.dart';
import 'admin_home_page.dart';
import 'dt_home_page.dart';
import 'generic_home_page.dart';

/// Router Home: delega a pagina dedicata per admin, DT o altri ruoli.
class HomePage extends StatelessWidget {
  final String username;
  final String fullName;
  final String role;
  final int userId;
  final String? secondaryRole;

  const HomePage({
    super.key,
    required this.username,
    required this.fullName,
    required this.role,
    required this.userId,
    this.secondaryRole,
  });

  bool get _isAdminHome {
    final r = normalizeRole(role);
    if (r == 'dt' || r == 'assistente_dt') return false;
    if (const {'dipendente', 'dipendenti', 'user'}.contains(r)) return false;
    if (r == 'logistica') return false;
    return isAnyAdminRole(role) ||
        r == 'admin_formazione' ||
        r == 'admin_dpi';
  }

  bool get _isDtHome {
    final r = normalizeRole(role);
    return r == 'dt' || r == 'assistente_dt';
  }

  @override
  Widget build(BuildContext context) {
    if (_isAdminHome) {
      return AdminHomePage(
        username: username,
        fullName: fullName,
        role: role,
        userId: userId,
        secondaryRole: secondaryRole,
      );
    }
    if (_isDtHome) {
      return DtHomePage(
        username: username,
        fullName: fullName,
        role: role,
        userId: userId,
        secondaryRole: secondaryRole,
      );
    }
    return GenericHomePage(
      username: username,
      fullName: fullName,
      role: role,
      userId: userId,
      secondaryRole: secondaryRole,
    );
  }
}
