import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/pages/admin_page.dart';
import 'package:crm_app/pages/customer_open_page.dart';
import 'package:crm_app/pages/customer_page.dart';
import 'package:crm_app/pages/dashboard_page.dart';
import 'package:crm_app/pages/global_search_page.dart';
import 'package:crm_app/pages/home_page.dart';
import 'package:crm_app/pages/inventory_page.dart';
import 'package:crm_app/pages/leads_page.dart';
import 'package:crm_app/pages/settings_page.dart';
import 'package:crm_app/pages/wired_members_page.dart';

class AppLayout extends StatefulWidget {
  final String role;
  final String store;

  const AppLayout({super.key, required this.role, required this.store});

  @override
  State<AppLayout> createState() => _AppLayoutState();
}

class _AppLayoutState extends State<AppLayout> {
  int selectedIndex = 0;
  final globalNameSearchController = TextEditingController();
  final globalPhoneSearchController = TextEditingController();
  String globalNameQuery = '';
  String globalPhoneQuery = '';
  String pageSearchNameQuery = '';
  String pageSearchPhoneQuery = '';
  String pageSearchKeyword = '';

  bool get isAdminRole => widget.role == '대표' || widget.role == '개발자';
  bool get isPublicRole => widget.role == '조회용' || widget.role == '공개용';

  List<_NavItem> get items {
    if (isPublicRole) {
      return [
        _NavItem(
          title: '고객등록',
          icon: Icons.edit_note_rounded,
          page: HomePage(role: widget.role, currentStore: widget.store),
        ),
        _NavItem(
          title: '고객DBS',
          icon: Icons.people_alt_rounded,
          page: CustomerOpenPage(
            role: widget.role,
            currentStore: widget.store,
          ),
        ),
        _NavItem(
          title: '재고관리',
          icon: Icons.inventory_2_rounded,
          page: InventoryPage(role: widget.role, currentStore: widget.store),
        ),
        _NavItem(
          title: '설정',
          icon: Icons.settings_rounded,
          page: SettingsPage(role: widget.role, currentStore: widget.store),
        ),
      ];
    }

    return [
      _NavItem(
        title: '고객등록',
        icon: Icons.edit_note_rounded,
        page: HomePage(role: widget.role, currentStore: widget.store),
      ),
      _NavItem(
        title: '고객DB',
        icon: Icons.people_alt_rounded,
        page: CustomerPage(
          role: widget.role,
          currentStore: widget.store,
          initialNameQuery: pageSearchNameQuery,
          initialPhoneQuery: pageSearchPhoneQuery,
        ),
      ),
      _NavItem(
        title: '가망고객',
        icon: Icons.person_search_rounded,
        page: LeadsPage(
          role: widget.role,
          currentStore: widget.store,
          initialSearchQuery: pageSearchKeyword,
        ),
      ),
      _NavItem(
        title: '유선회원',
        icon: Icons.cable_rounded,
        page: WiredMembersPage(
          role: widget.role,
          currentStore: widget.store,
          initialSearchQuery: pageSearchKeyword,
        ),
      ),
      _NavItem(
        title: '대시보드',
        icon: Icons.dashboard_rounded,
        page: DashboardPage(role: widget.role, currentStore: widget.store),
      ),
      _NavItem(
        title: '재고관리',
        icon: Icons.inventory_2_rounded,
        page: InventoryPage(role: widget.role, currentStore: widget.store),
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
        page: SettingsPage(role: widget.role, currentStore: widget.store),
      ),
      _NavItem(
        title: '통합검색',
        icon: Icons.search_rounded,
        page: GlobalSearchPage(
          key: ValueKey('$globalNameQuery|$globalPhoneQuery'),
          nameQuery: globalNameQuery,
          phoneQuery: globalPhoneQuery,
          role: widget.role,
          currentStore: widget.store,
          onNavigateToPage: _selectPageByTitle,
        ),
      ),
    ];
  }

  int get searchPageIndex => items.indexWhere((item) => item.title == '통합검색');

  void _selectPageByTitle(String title) {
    final index = items.indexWhere((item) => item.title == title);
    if (index < 0) return;
    final keyword = globalPhoneQuery.trim().isNotEmpty
        ? globalPhoneQuery.trim()
        : globalNameQuery.trim();
    setState(() {
      if (title == '고객DB') {
        pageSearchNameQuery = globalNameQuery;
        pageSearchPhoneQuery = globalPhoneQuery;
      } else if (title == '가망고객' || title == '유선회원') {
        pageSearchKeyword = keyword;
      }
      selectedIndex = index;
    });
  }

  void _runGlobalSearch() {
    final name = globalNameSearchController.text.trim();
    final phone = globalPhoneSearchController.text.trim();
    final searchIndex = searchPageIndex;
    if (searchIndex < 0) return;

    if (name.isEmpty && phone.isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('고객명 또는 핸드폰번호를 입력해 주세요')),
      );
      return;
    }

    setState(() {
      globalNameQuery = name;
      globalPhoneQuery = phone;
      selectedIndex = searchIndex;
      globalNameSearchController.clear();
      globalPhoneSearchController.clear();
    });
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: const Text(
              '로그아웃',
              style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
            content: const Text(
              '현재 계정에서 로그아웃하시겠습니까?',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                ),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC94C6E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('로그아웃'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldLogout) return;

    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: const Text('프로그램 종료'),
            content: const Text('CRM을 종료하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                ),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC94C6E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('종료'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldExit) return;

    await Supabase.instance.client.auth.signOut();

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

  Widget _topSearchField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    double width = 210,
  }) {
    return SizedBox(
      width: width,
      height: 36,
      child: TextField(
        controller: controller,
        onSubmitted: (_) => _runGlobalSearch(),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, size: 17, color: const Color(0xFF9CA3AF)),
          filled: true,
          fillColor: const Color(0xFFF4F5F8),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE8E9EF)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE8E9EF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFC94C6E)),
          ),
        ),
      ),
    );
  }

  Widget _topBar(_NavItem currentItem) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE8E9EF)),
        ),
      ),
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentItem.title,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                isPublicRole ? '조회용 권한' : '고객명 또는 핸드폰번호로 전체 데이터 검색',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (!isPublicRole) ...[
            _topSearchField(
              controller: globalNameSearchController,
              hint: '고객명 검색',
              icon: Icons.person_search_outlined,
              width: 180,
            ),
            const SizedBox(width: 8),
            _topSearchField(
              controller: globalPhoneSearchController,
              hint: '핸드폰번호 검색',
              icon: Icons.phone_iphone_outlined,
              width: 200,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 36,
              height: 36,
              child: ElevatedButton(
                onPressed: _runGlobalSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC94C6E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Icon(Icons.search_rounded, size: 18),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    globalNameSearchController.dispose();
    globalPhoneSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navItems = items;
    final settingsIndex = navItems.indexWhere((item) => item.title == '설정');
    final visibleNavIndexes = [
      for (var i = 0; i < navItems.length; i++)
        if (navItems[i].title != '설정') i,
    ];

    if (selectedIndex >= navItems.length) {
      selectedIndex = 0;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: 232,
              decoration: const BoxDecoration(
                color: Color(0xFF191B2A),
                border: Border(
                  right: BorderSide(color: Color(0xFF252740)),
                ),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0xFFC94C6E),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.phone_rounded,
                              size: 16, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '핑크폰',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '권한: ${widget.role}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF7C7F96),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: const Color(0xFFC94C6E)
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.bolt_rounded,
                              size: 12,
                              color: Color(0xFFC94C6E),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.store.isEmpty ? '-' : widget.store,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFD1D3E0),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 14,
                            color: Color(0xFF7C7F96),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFF252740)),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: visibleNavIndexes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final navIndex = visibleNavIndexes[index];
                        final item = navItems[navIndex];
                        final selected = selectedIndex == navIndex;

                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            setState(() {
                              selectedIndex = navIndex;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFFC94C6E)
                                      .withValues(alpha: 0.14)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  item.icon,
                                  color: selected
                                      ? const Color(0xFFC94C6E)
                                      : const Color(0xFF8A8DA6),
                                  size: 18,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    item.title,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? Colors.white
                                          : const Color(0xFF8A8DA6),
                                    ),
                                  ),
                                ),
                                if (selected)
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFC94C6E),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFF252740)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                    child: Column(
                      children: [
                        if (settingsIndex >= 0) ...[
                          InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              setState(() {
                                selectedIndex = settingsIndex;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: selectedIndex == settingsIndex
                                    ? const Color(0xFFC94C6E)
                                        .withValues(alpha: 0.14)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF252740),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.settings_rounded,
                                    color: selectedIndex == settingsIndex
                                        ? const Color(0xFFC94C6E)
                                        : const Color(0xFF8A8DA6),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '설정',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: selectedIndex == settingsIndex
                                            ? Colors.white
                                            : const Color(0xFF8A8DA6),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _confirmLogout,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF252740),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.logout_rounded,
                                  color: Color(0xFF8A8DA6),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '로그아웃',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFD1D3E0),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _confirmExit,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFF252740)),
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  _topBar(navItems[selectedIndex]),
                  Expanded(
                    child: IndexedStack(
                      index: selectedIndex,
                      children: navItems.map((e) => e.page).toList(),
                    ),
                  ),
                ],
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
