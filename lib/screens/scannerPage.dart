import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../widgets/pidScanner.dart';

@RoutePage()
class scannerpage extends StatelessWidget {
  const scannerpage({super.key});

  @override
  Widget build(BuildContext context) => const PidScanner();
}
