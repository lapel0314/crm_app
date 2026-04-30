import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/pages/admin_page.dart';
import 'package:crm_app/pages/audit_log_page.dart';
import 'package:crm_app/pages/customer_open_page.dart';
import 'package:crm_app/pages/customer_page.dart';
import 'package:crm_app/pages/dashboard_page.dart';
import 'package:crm_app/pages/global_search_page.dart';
import 'package:crm_app/pages/home_page.dart';
import 'package:crm_app/pages/inventory_page.dart';
import 'package:crm_app/pages/leads_page.dart';
import 'package:crm_app/pages/rebate_page.dart';
import 'package:crm_app/pages/recycle_bin_page.dart';
import 'package:crm_app/pages/settings_page.dart';
import 'package:crm_app/pages/store_management_page.dart';
import 'package:crm_app/pages/wired_members_page.dart';
import 'package:crm_app/services/notice_service.dart';
import 'package:crm_app/utils/store_utils.dart';

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
  final noticeService = NoticeService(Supabase.instance.client);
  Notice? latestNotice;
  List<Notice> notices = [];
  bool isNoticeLoading = false;
  DateTime? lastNoticeReadAt;
  int noticePage = 0;
  static const int noticePageSize = 10;

  bool get isAdminRole => isPrivilegedRole(widget.role);

  List<_NavItem> get items {
    return [
      _NavItem(
        title: '고객등록',
        icon: Icons.edit_note_rounded,
        page: HomePage(role: widget.role, currentStore: widget.store),
      ),
      if (canUseCustomerDb(widget.role))
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
      if (canUseOpenCustomerDb(widget.role))
        _NavItem(
          title: '고객DBS',
          icon: Icons.people_alt_rounded,
          page: CustomerOpenPage(role: widget.role, currentStore: widget.store),
        ),
      if (canUseLeads(widget.role))
        _NavItem(
          title: '가망고객',
          icon: Icons.person_search_rounded,
          page: LeadsPage(
            role: widget.role,
            currentStore: widget.store,
            initialSearchQuery: pageSearchKeyword,
          ),
        ),
      if (canUseWiredMembers(widget.role))
        _NavItem(
          title: '유선회원',
          icon: Icons.cable_rounded,
          page: WiredMembersPage(
            role: widget.role,
            currentStore: widget.store,
            initialSearchQuery: pageSearchKeyword,
          ),
        ),
      if (canUseDashboard(widget.role))
        _NavItem(
          title: '대시보드',
          icon: Icons.dashboard_rounded,
          page: DashboardPage(role: widget.role, currentStore: widget.store),
        ),
      if (canUseInventory(widget.role))
        _NavItem(
          title: '재고관리',
          icon: Icons.inventory_2_rounded,
          page: InventoryPage(role: widget.role, currentStore: widget.store),
        ),
      if (canViewRebate(widget.role))
        _NavItem(
          title: '리베이트',
          icon: Icons.image_rounded,
          page: RebatePage(role: widget.role),
          quickOnly: true,
        ),
      if (isAdminRole)
        _NavItem(
          title: '직원관리',
          icon: Icons.admin_panel_settings_rounded,
          page: AdminPage(role: widget.role),
        ),
      if (isAdminRole)
        _NavItem(
          title: '매장관리',
          icon: Icons.store_mall_directory_rounded,
          page: StoreManagementPage(
            role: widget.role,
            currentStore: widget.store,
          ),
        ),
      if (isAdminRole)
        _NavItem(
          title: '휴지통',
          icon: Icons.restore_from_trash_rounded,
          page: RecycleBinPage(role: widget.role),
        ),
      if (isAdminRole)
        _NavItem(
          title: '감사로그',
          icon: Icons.manage_search_rounded,
          page: AuditLogPage(role: widget.role),
        ),
      if (canUseSettings(widget.role))
        _NavItem(
          title: '설정',
          icon: Icons.settings_rounded,
          page: SettingsPage(role: widget.role, currentStore: widget.store),
        ),
      if (canUseGlobalSearch(widget.role))
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
          quickOnly: true,
        ),
    ];
  }

  int get searchPageIndex => items.indexWhere((item) => item.title == '통합검색');

  @override
  void initState() {
    super.initState();
    _loadNoticeReadAt();
    _loadLatestNotice();
  }

  Future<void> _loadNoticeReadAt() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('last_notice_read_at');
    if (!mounted) return;
    setState(() {
      lastNoticeReadAt = DateTime.tryParse(value ?? '');
    });
  }

  Future<void> _loadLatestNotice() async {
    setState(() {
      isNoticeLoading = true;
    });

    final notice = await noticeService.fetchLatestNotice();
    final noticeRows = await noticeService.fetchNotices();
    if (!mounted) return;
    setState(() {
      latestNotice = notice;
      notices = noticeRows;
      if (noticePage * noticePageSize >= noticeRows.length) {
        noticePage = 0;
      }
      isNoticeLoading = false;
    });
  }

  bool get hasUnreadNotice {
    final createdAt = latestNotice?.createdAt;
    if (createdAt == null) return false;
    final readAt = lastNoticeReadAt;
    return readAt == null || createdAt.isAfter(readAt);
  }

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('고객명 또는 핸드폰번호를 입력해 주세요')));
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            title: const Text(
              '\uB85C\uADF8\uC544\uC6C3',
              style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
            content: const Text(
              '\uD604\uC7AC \uACC4\uC815\uC5D0\uC11C \uB85C\uADF8\uC544\uC6C3\uD558\uC2DC\uACA0\uC2B5\uB2C8\uAE4C?',
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
                child: const Text('\uCDE8\uC18C'),
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
                child: const Text('\uB85C\uADF8\uC544\uC6C3'),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
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

  Future<void> _showNoticePopup() async {
    await _loadLatestNotice();
    if (!mounted) return;
    final readAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_notice_read_at', readAt.toIso8601String());
    if (mounted) {
      setState(() {
        lastNoticeReadAt = readAt;
      });
    }

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final screenSize = MediaQuery.of(context).size;
          final compact = screenSize.width < 900;
          final totalPages = notices.isEmpty
              ? 1
              : ((notices.length - 1) ~/ noticePageSize) + 1;
          final pageItems = notices
              .skip(noticePage * noticePageSize)
              .take(noticePageSize)
              .toList();

          return AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: const Text(
              '공지사항',
              style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
            content: SizedBox(
              width: compact ? screenSize.width - 56 : 620,
              height: compact ? screenSize.height * 0.62 : 540,
              child: notices.isEmpty
                  ? const Center(child: Text('등록된 공지사항이 없습니다.'))
                  : Column(
                      children: [
                        Expanded(
                          child: ListView.separated(
                            itemCount: pageItems.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              return _noticeTile(
                                pageItems[index],
                                setDialogState,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: noticePage == 0
                                  ? null
                                  : () {
                                      setDialogState(() => noticePage--);
                                      setState(() {});
                                    },
                              child: const Text('이전'),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('${noticePage + 1} / $totalPages'),
                            ),
                            TextButton(
                              onPressed: noticePage >= totalPages - 1
                                  ? null
                                  : () {
                                      setDialogState(() => noticePage++);
                                      setState(() {});
                                    },
                              child: const Text('다음'),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteNoticeFromPopup(
    BuildContext context,
    Notice notice,
    void Function(void Function()) setDialogState,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('공지사항 삭제'),
            content: Text('"${notice.title}" 공지사항을 삭제하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    try {
      await noticeService.deleteNotice(notice);
      final refreshed = await noticeService.fetchNotices();
      if (!mounted) return;

      setDialogState(() {
        notices = refreshed;
        final totalPages = refreshed.isEmpty
            ? 1
            : ((refreshed.length - 1) ~/ noticePageSize) + 1;
        if (noticePage >= totalPages) {
          noticePage = totalPages - 1;
        }
        if (noticePage < 0) {
          noticePage = 0;
        }
      });
      setState(() {});

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공지사항이 삭제되었습니다.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      final message = e is PostgrestException ? e.message : e.toString();
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('공지사항 삭제 실패: $message')),
      );
    }
  }

  String _noticeTime(Notice notice) {
    final date = notice.createdAt?.toLocal();
    if (date == null) return '-';
    return DateFormat('MM/dd HH:mm').format(date);
  }

  Widget _noticeTile(Notice notice, StateSetter setDialogState) {
    return FutureBuilder<String?>(
      future: notice.hasImage
          ? noticeService.signedImageUrl(notice.imagePath)
          : Future.value(null),
      builder: (context, snapshot) {
        final imageUrl = snapshot.data;
        return ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE8E9EF)),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE8E9EF)),
          ),
          title: Row(
            children: [
              SizedBox(
                width: 78,
                child: Text(
                  _noticeTime(notice),
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (notice.isToday)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFDC2626),
                    shape: BoxShape.circle,
                  ),
                ),
              Expanded(
                child: Text(
                  notice.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (isAdminRole)
                IconButton(
                  tooltip: '삭제',
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      _deleteNoticeFromPopup(context, notice, setDialogState),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Color(0xFFDC2626),
                  ),
                ),
            ],
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                notice.content,
                style: const TextStyle(
                  color: Color(0xFF4B5563),
                  height: 1.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (imageUrl != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(imageUrl, fit: BoxFit.contain),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _topBar(_NavItem currentItem) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8E9EF))),
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
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _quickTopBar(List<_NavItem> navItems) {
    final rebateIndex = navItems.indexWhere((item) => item.title == '리베이트');

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 7),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(bottom: BorderSide(color: Color(0xFF252740))),
      ),
      child: Row(
        children: [
          _quickButton(
            icon: Icons.notifications_active_outlined,
            label: '공지사항',
            accent: hasUnreadNotice,
            onTap: isNoticeLoading ? null : _showNoticePopup,
            width: 150,
          ),
          if (rebateIndex >= 0) ...[
            const SizedBox(width: 8),
            _quickButton(
              icon: Icons.image_rounded,
              label: '리베이트',
              selected: selectedIndex == rebateIndex,
              onTap: () {
                setState(() => selectedIndex = rebateIndex);
              },
              width: 116,
            ),
          ],
          if (canUseGlobalSearch(widget.role)) ...[
            const Spacer(),
            _quickSearchField(
              controller: globalNameSearchController,
              hint: '고객명 검색',
              icon: Icons.person_search_outlined,
              width: 180,
            ),
            const SizedBox(width: 8),
            _quickSearchField(
              controller: globalPhoneSearchController,
              hint: '핸드폰번호 검색',
              icon: Icons.phone_iphone_outlined,
              width: 200,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 124,
              height: 34,
              child: ElevatedButton.icon(
                onPressed: _runGlobalSearch,
                icon: const Icon(Icons.search_rounded, size: 16),
                label: const Text('통합검색'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC94C6E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _quickButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool accent = false,
    bool selected = false,
    double? width,
  }) {
    final color = accent
        ? const Color(0xFFDC2626)
        : selected
            ? const Color(0xFFC94C6E)
            : const Color(0xFF8A8DA6);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: width,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent
                      ? const Color(0xFFFFD6D6)
                      : const Color(0xFFD1D3E0),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (accent)
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFFDC2626),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _quickSearchField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    double? width,
  }) {
    return SizedBox(
      width: width,
      height: 34,
      child: TextField(
        controller: controller,
        onSubmitted: (_) => _runGlobalSearch(),
        style: const TextStyle(fontSize: 12, color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF7C7F96)),
          prefixIcon: Icon(icon, size: 16, color: const Color(0xFF8A8DA6)),
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF252740)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF252740)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFC94C6E)),
          ),
        ),
      ),
    );
  }

  Widget _iosCompactLayout(
    BuildContext context,
    List<_NavItem> navItems,
    List<int> visibleNavIndexes,
    int settingsIndex,
  ) {
    final currentItem = navItems[selectedIndex];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      drawer: Drawer(
        backgroundColor: const Color(0xFF191B2A),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFFC94C6E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.phone_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
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
                          color:
                              const Color(0xFFC94C6E).withValues(alpha: 0.14),
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
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFF252740)),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final navIndex in visibleNavIndexes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _compactDrawerItem(
                          item: navItems[navIndex],
                          selected: selectedIndex == navIndex,
                          onTap: () {
                            Navigator.pop(context);
                            setState(() {
                              selectedIndex = navIndex;
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF252740)),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                child: Column(
                  children: [
                    if (settingsIndex >= 0) ...[
                      _compactDrawerItem(
                        item: navItems[settingsIndex],
                        selected: selectedIndex == settingsIndex,
                        onTap: () {
                          Navigator.pop(context);
                          setState(() {
                            selectedIndex = settingsIndex;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                    _compactActionItem(
                      icon: Icons.logout_rounded,
                      label: '로그아웃',
                      color: const Color(0xFF8A8DA6),
                      onTap: () {
                        Navigator.pop(context);
                        _confirmLogout();
                      },
                    ),
                    const SizedBox(height: 8),
                    _compactActionItem(
                      icon: Icons.power_settings_new_rounded,
                      label: '종료',
                      color: const Color(0xFFDC2626),
                      onTap: () {
                        Navigator.pop(context);
                        _confirmExit();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: const Color(0xFF191B2A),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentItem.title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            Text(
              widget.store.isEmpty ? '-' : widget.store,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFB5B8C9),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: isNoticeLoading ? null : _showNoticePopup,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_active_outlined),
                if (hasUnreadNotice)
                  const Positioned(
                    right: -1,
                    top: -1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFFDC2626),
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(width: 8, height: 8),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: selectedIndex,
          children: navItems.map((e) => e.page).toList(),
        ),
      ),
    );
  }

  Widget _compactDrawerItem({
    required _NavItem item,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFC94C6E).withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              color:
                  selected ? const Color(0xFFC94C6E) : const Color(0xFF8A8DA6),
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFF8A8DA6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactActionItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF252740)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
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
        if (navItems[i].title != '설정' && !navItems[i].quickOnly) i,
    ];

    if (selectedIndex >= navItems.length) {
      selectedIndex = 0;
    }

    final useCompactLayout = !kIsWeb && MediaQuery.of(context).size.width < 900;
    if (useCompactLayout) {
      return _iosCompactLayout(
        context,
        navItems,
        visibleNavIndexes,
        settingsIndex,
      );
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
                border: Border(right: BorderSide(color: Color(0xFF252740))),
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
                          child: const Icon(
                            Icons.phone_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
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
                              color: const Color(
                                0xFFC94C6E,
                              ).withValues(alpha: 0.14),
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
                                  ? const Color(
                                      0xFFC94C6E,
                                    ).withValues(alpha: 0.14)
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
                                    ? const Color(
                                        0xFFC94C6E,
                                      ).withValues(alpha: 0.14)
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
                                    '\uB85C\uADF8\uC544\uC6C3',
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
                              border: Border.all(
                                color: const Color(0xFF252740),
                              ),
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
                  _quickTopBar(navItems),
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
  final bool quickOnly;

  _NavItem({
    required this.title,
    required this.icon,
    required this.page,
    this.quickOnly = false,
  });
}
