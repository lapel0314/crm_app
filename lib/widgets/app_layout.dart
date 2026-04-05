import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crm_app/pages/admin_page.dart';
import 'package:crm_app/pages/customer_page.dart';
import 'package:crm_app/pages/dashboard_page.dart';
import 'package:crm_app/pages/home_page.dart';
import 'package:crm_app/pages/inventory_page.dart';
import 'package:crm_app/pages/leads_page.dart';
import 'package:crm_app/pages/settings_page.dart';
import 'package:crm_app/pages/wired_members_page.dart';

class AppLayout extends StatefulWidget {
  final String role;

  const AppLayout({super.key, required this.role});

  @override
  State<AppLayout> createState() => _AppLayoutState();
}

class _AppLayoutState extends State<AppLayout> {
  int selectedIndex = 0;

  bool get isAdminRole => widget.role == '대표' || widget.role == '개발자';
  bool get isPublicRole => widget.role == '공개용';

  List<_NavItem> get items {
    if (isPublicRole) {
      return [
        _NavItem(
          title: '고객DB',
          icon: Icons.people_alt_rounded,
          page: CustomerPage(role: widget.role),
        ),
      ];
    }

    return [
      _NavItem(
        title: '고객등록',
        icon: Icons.edit_note_rounded,
        page: HomePage(role: widget.role),
      ),
      _NavItem(
        title: '고객DB',
        icon: Icons.people_alt_rounded,
        page: CustomerPage(role: widget.role),
      ),
      _NavItem(
        title: '가망고객',
        icon: Icons.person_search_rounded,
        page: LeadsPage(role: widget.role),
      ),
      _NavItem(
        title: '유선회원',
        icon: Icons.cable_rounded,
        page: WiredMembersPage(role: widget.role),
      ),
      _NavItem(
        title: '대시보드',
        icon: Icons.dashboard_rounded,
        page: const DashboardPage(),
      ),
      _NavItem(
        title: '재고관리',
        icon: Icons.inventory_2_rounded,
        page: InventoryPage(role: widget.role),
      ),
      if (isAdminRole)
        _NavItem(
          title: '직원관리',
          icon: Icons.admin_panel_settings_rounded,
          page: AdminPage(role: widget.role),
        ),
      _NavItem(
        title: '설정',
        icon: Icons.settings_rounded,
        page: SettingsPage(role: widget.role),
      ),
    ];
  }

  Future<void> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('프로그램 종료'),
            content: const Text('CRM을 종료하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('종료'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldExit) return;

    if (kIsWeb) return;

    try {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        exit(0);
      } else {
        await SystemNavigator.pop();
      }
    } catch (_) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final navItems = items;

    if (selectedIndex >= navItems.length) {
      selectedIndex = 0;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: 230,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  right: BorderSide(color: Color(0xFFE7E9EE)),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pink Phone CRM',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '권한: ${widget.role}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: navItems.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final item = navItems[index];
                        final selected = selectedIndex == index;

                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            setState(() {
                              selectedIndex = index;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFFFFEEF5)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFFFFC6DF)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  item.icon,
                                  color: selected
                                      ? const Color(0xFFFF2D8D)
                                      : const Color(0xFF6B7280),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    item.title,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? const Color(0xFFFF2D8D)
                                          : const Color(0xFF111827),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _confirmExit,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFFD4D8)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.power_settings_new_rounded,
                              color: Color(0xFFDC2626),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '종료',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: selectedIndex,
                children: navItems.map((e) => e.page).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final String title;
  final IconData icon;
  final Widget page;

  _NavItem({
    required this.title,
    required this.icon,
    required this.page,
  });
}
