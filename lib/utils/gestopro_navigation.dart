import 'package:flutter/material.dart';



import '../utils/futuristic_navigation.dart';

import '../widgets/futuristic/futuristic_page_shell.dart';



/// Apre una pagina nell'interfaccia GESTOPRO / futuristica.

Future<T?> openGestoproPage<T>(

  BuildContext context, {

  required Widget page,

  String? title,

}) {

  return FuturisticNavigation.pushPage<T>(

    context,

    page: page,

    title: title,

  );

}



/// Forza la shell futuristica (sessione GESTOPRO).

Future<T?> openGestoproPageForced<T>(

  BuildContext context, {

  required Widget page,

  String? title,

}) {

  return Navigator.push<T>(

    context,

    MaterialPageRoute(

      builder: (_) => FuturisticPageShell(

        title: title,

        child: page,

      ),

    ),

  );

}


