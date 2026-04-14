import 'package:flutter/material.dart';
import 'package:crm_app/pages/customer_page.dart';

class CustomerOpenPage extends StatelessWidget {
  final String role;
  final String currentStore;

  const CustomerOpenPage({
    super.key,
    required this.role,
    required this.currentStore,
  });

  @override
  Widget build(BuildContext context) {
    return CustomerPage(
      role: role,
      currentStore: currentStore,
      openMode: true,
    );
  }
}
