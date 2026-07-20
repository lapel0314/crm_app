import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/pages/admin_page.dart';
import 'package:crm_app/pages/customer_open_page.dart';
import 'package:crm_app/pages/customer_page.dart';
import 'package:crm_app/pages/data_quality_page.dart';
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
import 'package:crm_app/services/audit_log_service.dart';
import 'package:crm_app/services/customer_excel_export_service.dart';
import 'package:crm_app/services/desktop_auth_session_service.dart';
import 'package:crm_app/services/notice_service.dart';
import 'package:crm_app/services/plan_change_alert_service.dart';
import 'package:crm_app/utils/store_utils.dart';
import 'package:crm_app/widgets/plan_change_alert_dialog.dart';

class AppLayout extends StatefulWidget {
  final String role;
  final String store;

  const AppLayout({super.key, required this.role, required this.store});

  @override
  State<AppLayout> createState() => _AppLayoutState();
}

class _AppLayoutState extends State<AppLayout> {
  int selectedIndex = 0;
  late String activeStore;
  final globalNameSearchController = TextEditingController();
  final globalPhoneSearchController = TextEditingController();
  String globalNameQuery = '';
  String globalPhoneQuery = '';
  String pageSearchNameQuery = '';
  String pageSearchPhoneQuery = '';
  String pageSearchKeyword = '';
  final noticeService = NoticeService(Supabase.instance.client);
  final planAlertService = PlanChangeAlertService(Supabase.instance.client);
  final customerExcelExportService = const CustomerExcelExportService();
  final auditLogService = AuditLogService();
  Notice? latestNotice;
  List<Notice> notices = [];
  bool isNoticeLoading = false;
  bool isPlanAlertLoading = false;
  bool isStoreAccordionOpen = false;
  bool isStoreListLoading = false;
  bool hasLoadedStoreList = false;
  bool isAddingStore = false;
  PlanChangeAlertResult? todayPlanAlert;
  List<_StoreOption> storeOptions = [];
  DateTime? lastNoticeReadAt;
  int noticePage = 0;
  static const int noticePageSize = 10;

  bool get isAdminRole => isPrivilegedRole(widget.role);
  bool get canAddStores => isPrivilegedRole(widget.role);
  String get displayStore => activeStore.isEmpty ? '전체 매장' : activeStore;

  List<_NavItem> get items {
    return [
      _NavItem(
        title: '고객등록',
        icon: Icons.edit_note_rounded,
        page: HomePage(role: widget.role, currentStore: activeStore),
      ),
      if (canUseCustomerDb(widget.role))
        _NavItem(
          title: '고객DB',
          icon: Icons.people_alt_rounded,
          page: CustomerPage(
            role: widget.role,
            currentStore: activeStore,
            initialNameQuery: pageSearchNameQuery,
            initialPhoneQuery: pageSearchPhoneQuery,
          ),
        ),
      if (canUseOpenCustomerDb(widget.role))
        _NavItem(
          title: '고객DBS',
          icon: Icons.people_alt_rounded,
          page: CustomerOpenPage(role: widget.role, currentStore: activeStore),
        ),
      if (canUseLeads(widget.role))
        _NavItem(
          title: '가망고객',
          icon: Icons.person_search_rounded,
          page: LeadsPage(
            role: widget.role,
            currentStore: activeStore,
            initialSearchQuery: pageSearchKeyword,
          ),
        ),
      if (canUseWiredMembers(widget.role))
        _NavItem(
          title: '유선회원',
          icon: Icons.cable_rounded,
          page: WiredMembersPage(
            role: widget.role,
            currentStore: activeStore,
            initialSearchQuery: pageSearchKeyword,
          ),
        ),
      if (canUseDashboard(widget.role))
        _NavItem(
          title: '대시보드',
          icon: Icons.dashboard_rounded,
          page: DashboardPage(role: widget.role, currentStore: activeStore),
        ),
      if (canUseInventory(widget.role))
        _NavItem(
          title: '재고관리',
          icon: Icons.inventory_2_rounded,
          page: InventoryPage(role: widget.role, currentStore: activeStore),
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
            currentStore: activeStore,
            onStoreDeleted: _handleStoreDeleted,
          ),
        ),
      if (isAdminRole)
        _NavItem(
          title: '삭제자료',
          icon: Icons.restore_from_trash_rounded,
          page: RecycleBinPage(
            role: widget.role,
            onNavigateToPage: _selectPageByTitle,
          ),
        ),
      if (isAdminRole)
        _NavItem(
          title: '고객정리',
          icon: Icons.fact_check_rounded,
          page: DataQualityPage(
            role: widget.role,
            currentStore: activeStore,
          ),
        ),
      if (canUseSettings(widget.role))
        _NavItem(
          title: '설정',
          icon: Icons.settings_rounded,
          page: SettingsPage(role: widget.role, currentStore: activeStore),
        ),
      if (canUseGlobalSearch(widget.role))
        _NavItem(
          title: '통합검색',
          icon: Icons.search_rounded,
          page: GlobalSearchPage(
            key: ValueKey('$globalNameQuery|$globalPhoneQuery|$activeStore'),
            nameQuery: globalNameQuery,
            phoneQuery: globalPhoneQuery,
            role: widget.role,
            currentStore: activeStore,
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
    activeStore =
        isPrivilegedRole(widget.role) ? '' : normalizeStoreName(widget.store);
    _loadNoticeReadAt();
    _loadLatestNotice();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowTodayPlanAlert();
    });
  }

  @override
  void didUpdateWidget(covariant AppLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!isPrivilegedRole(widget.role) &&
        !isSameStore(oldWidget.store, widget.store) &&
        activeStore.isEmpty) {
      activeStore = normalizeStoreName(widget.store);
    }
  }

  String _planAlertUserKey() {
    final user = Supabase.instance.client.auth.currentUser;
    return user?.id ?? user?.email ?? 'anonymous';
  }

  String _planAlertDateKey(DateTime date) {
    return DateFormat('yyyyMMdd').format(date);
  }

  String _planAlertAutoShownKey(DateTime date) {
    return 'plan_alert_auto_shown_${_planAlertUserKey()}_${_planAlertDateKey(date)}';
  }

  String _planAlertHideTodayKey(DateTime date) {
    return 'plan_alert_hide_today_${_planAlertUserKey()}_${_planAlertDateKey(date)}';
  }

  Future<void> _maybeShowTodayPlanAlert() async {
    if (!canUseCustomerDb(widget.role)) return;
    final today = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final autoShown = prefs.getBool(_planAlertAutoShownKey(today)) ?? false;
    final hideToday = prefs.getBool(_planAlertHideTodayKey(today)) ?? false;
    if (autoShown || hideToday) return;
    if (!mounted) return;
    await _openTodayPlanAlert(automatic: true);
  }

  Future<PlanChangeAlertResult?> _fetchTodayPlanAlert({
    bool showError = false,
  }) async {
    if (isPlanAlertLoading) return todayPlanAlert;
    if (mounted) {
      setState(() => isPlanAlertLoading = true);
    }

    try {
      final result = await planAlertService.fetchTodayAlerts(
        role: widget.role,
        currentStore: activeStore,
      );
      if (!mounted) return result;
      setState(() {
        todayPlanAlert = result;
        isPlanAlertLoading = false;
      });
      return result;
    } catch (e) {
      if (!mounted) return null;
      setState(() => isPlanAlertLoading = false);
      if (showError) {
        _showMessage('오늘 알림 조회 실패: $e');
      }
      return null;
    }
  }

  Future<void> _openTodayPlanAlert({bool automatic = false}) async {
    if (!canUseCustomerDb(widget.role)) return;
    final result = await _fetchTodayPlanAlert(showError: !automatic);
    if (result == null || !mounted) return;

    if (automatic) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_planAlertAutoShownKey(result.date), true);
    }
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) => PlanChangeAlertDialog(
        result: result,
        onHideToday: () => _hideTodayPlanAlert(result.date),
        onExport: () => _exportPlanAlertExcel(result),
        onComplete: _completePlanAlertEntry,
        canExport: isPrivilegedRole(widget.role),
      ),
    );
  }

  Future<void> _completePlanAlertEntry(
    PlanChangeAlertEntry entry,
    String afterValue,
    String note,
  ) async {
    final task = entry.task;
    if (task == null) {
      _showMessage('처리 작업을 찾을 수 없습니다. 알림을 새로고침해 주세요.');
      return;
    }
    await planAlertService.completeTask(
      task: task,
      afterValue: afterValue,
      note: note,
    );
    await _fetchTodayPlanAlert();
    if (mounted) _showMessage('처리완료로 기록했습니다.');
  }

  Future<void> _hideTodayPlanAlert(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_planAlertHideTodayKey(date), true);
    await prefs.setBool(_planAlertAutoShownKey(date), true);
  }

  Future<void> _exportPlanAlertExcel(PlanChangeAlertResult result) async {
    if (!isPrivilegedRole(widget.role)) return;

    final exportResult = await customerExcelExportService.exportCustomers(
      rows: result.uniqueCustomers,
      prefix: '오늘알림',
      selectedDateText: DateFormat('yyyy-MM-dd').format(result.date),
      fallbackDateLabel: '오늘',
    );
    if (!mounted || exportResult.cancelled) return;
    if (!exportResult.success) {
      _showMessage(exportResult.message);
      return;
    }

    await auditLogService.record(
      action: 'export_customers_excel',
      targetTable: 'customers',
      detail: {
        'row_count': result.uniqueCustomers.length,
        'alert_count': result.totalEntries,
        'target_date': DateFormat('yyyy-MM-dd').format(result.date),
        'file_name': exportResult.fileName,
        'store_filter': exportResult.storeLabel,
        'date_filter': exportResult.dateLabel,
      },
    );
    if (!mounted) return;
    _showMessage(exportResult.message);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleStoreAccordion() async {
    final willOpen = !isStoreAccordionOpen;
    setState(() {
      isStoreAccordionOpen = willOpen;
    });
    if (willOpen && !hasLoadedStoreList) {
      await _loadStores(showError: true);
    }
  }

  void _selectActiveStore(_StoreOption store) {
    final nextStore = normalizeStoreName(store.name);
    if (!store.allStores && isSameStore(nextStore, activeStore)) return;
    if (!isPrivilegedRole(widget.role)) {
      _showMessage('다른 매장 데이터 조회는 대표 또는 개발자만 가능합니다.');
      return;
    }
    if (store.allStores) {
      if (activeStore.isEmpty) return;
      setState(() {
        activeStore = '';
        pageSearchNameQuery = '';
        pageSearchPhoneQuery = '';
        pageSearchKeyword = '';
      });
      _showMessage('전체 매장 데이터로 전환했습니다.');
      return;
    }
    if (nextStore.isEmpty || isSameStore(nextStore, activeStore)) return;
    setState(() {
      activeStore = nextStore;
      pageSearchNameQuery = '';
      pageSearchPhoneQuery = '';
      pageSearchKeyword = '';
    });
    _showMessage('$nextStore 매장 데이터로 전환했습니다.');
  }

  void _handleStoreDeleted(String storeName) {
    final normalizedStore = normalizeStoreName(storeName);
    setState(() {
      storeOptions.removeWhere(
        (store) => normalizeStoreName(store.name) == normalizedStore,
      );
      if (isSameStore(activeStore, normalizedStore)) {
        activeStore = '';
      }
    });
  }

  Future<void> _loadStores({bool showError = false}) async {
    if (isStoreListLoading) return;
    setState(() => isStoreListLoading = true);

    try {
      final rows = await Supabase.instance.client
          .from('stores')
          .select('id, name, normalized_name, is_active')
          .eq('is_active', true)
          .order('name', ascending: true);

      final stores = rows
          .map((row) => _StoreOption.fromMap(Map<String, dynamic>.from(row)))
          .where((store) => store.name.isNotEmpty)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      if (!mounted) return;
      setState(() {
        storeOptions = stores;
        hasLoadedStoreList = true;
        isStoreListLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isStoreListLoading = false);
      if (showError) {
        _showMessage('매장 목록 조회 실패: $e');
      }
    }
  }

  Future<void> _showAddStoreDialog() async {
    if (!canAddStores || isAddingStore) return;
    final controller = TextEditingController();
    try {
      final storeName = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: const Text(
            '매장 추가',
            style: TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w900,
            ),
          ),
          content: SizedBox(
            width: 360,
            child: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (value) =>
                  Navigator.pop(dialogContext, value.trim()),
              decoration: InputDecoration(
                labelText: '매장명',
                hintText: '예: 이대점',
                prefixIcon: const Icon(Icons.storefront_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            ElevatedButton.icon(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('추가'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC94C6E),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      );
      if (storeName == null) return;
      await _createStore(storeName);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _createStore(String rawName) async {
    final storeName = normalizeStoreName(rawName);
    if (storeName.isEmpty) {
      _showMessage('매장명을 입력해 주세요.');
      return;
    }

    setState(() => isAddingStore = true);
    try {
      final row = await Supabase.instance.client
          .from('stores')
          .upsert(
            {
              'name': storeName,
              'normalized_name': storeName,
              'is_active': true,
              'created_by': Supabase.instance.client.auth.currentUser?.id,
            },
            onConflict: 'normalized_name',
          )
          .select('id, name, normalized_name, is_active')
          .single();

      final added = _StoreOption.fromMap(Map<String, dynamic>.from(row));
      if (!mounted) return;
      setState(() {
        storeOptions.removeWhere(
          (store) => normalizeStoreName(store.name) == added.normalizedName,
        );
        storeOptions.add(added);
        storeOptions.sort((a, b) => a.name.compareTo(b.name));
        activeStore = added.name;
        hasLoadedStoreList = true;
        isStoreAccordionOpen = true;
        isAddingStore = false;
      });
      _showMessage('${added.name} 매장을 추가했습니다.');
    } catch (e) {
      if (!mounted) return;
      setState(() => isAddingStore = false);
      final message = e is PostgrestException ? e.message : e.toString();
      _showMessage('매장 추가 실패: $message');
    }
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

    await DesktopAuthSessionService.signOutAndClear(Supabase.instance.client);
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

    await DesktopAuthSessionService.signOutAndClear(Supabase.instance.client);

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
          if (canUseCustomerDb(widget.role)) ...[
            const SizedBox(width: 8),
            _quickButton(
              icon: Icons.event_available_rounded,
              label: '오늘 알림',
              accent: todayPlanAlert?.entries.isNotEmpty == true,
              onTap: isPlanAlertLoading ? null : () => _openTodayPlanAlert(),
              width: 124,
            ),
          ],
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

  Widget _sidebarBrandHeader({required EdgeInsets padding}) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFC94C6E),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFC94C6E).withValues(alpha: 0.32),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.phone_iphone_rounded,
              size: 19,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '핑크폰',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '권한: ${widget.role}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _storeAccordion({required EdgeInsets padding}) {
    return Padding(
      padding: padding,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _toggleStoreAccordion,
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isStoreAccordionOpen
                    ? const Color(0xFFC94C6E).withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isStoreAccordionOpen
                      ? const Color(0xFFC94C6E).withValues(alpha: 0.38)
                      : const Color(0xFF252740),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC94C6E).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      size: 14,
                      color: Color(0xFFC94C6E),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '매장',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF7C7F96),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          displayStore,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFE5E7EB),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: isStoreAccordionOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Color(0xFF8A8DA6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: isStoreAccordionOpen
                ? _storeAccordionBody()
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }

  Widget _storeAccordionBody() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF252740)),
      ),
      child: Column(
        children: [
          if (isStoreListLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    '매장 조회 중',
                    style: TextStyle(
                      color: Color(0xFFD1D3E0),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          else if (storeOptions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                '등록된 매장이 없습니다.',
                style: TextStyle(
                  color: Color(0xFF8A8DA6),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 172),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: storeOptions.length +
                    (isPrivilegedRole(widget.role) ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final hasAllStores = isPrivilegedRole(widget.role);
                  final store = hasAllStores && index == 0
                      ? const _StoreOption.all()
                      : storeOptions[index - (hasAllStores ? 1 : 0)];
                  final selected = store.allStores
                      ? activeStore.isEmpty
                      : isSameStore(store.name, activeStore);
                  return _storeListRow(
                    store,
                    selected: selected,
                    onTap: () => _selectActiveStore(store),
                  );
                },
              ),
            ),
          if (canAddStores) ...[
            const SizedBox(height: 8),
            _addStoreButton(),
          ],
        ],
      ),
    );
  }

  Widget _storeListRow(
    _StoreOption store, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFC94C6E).withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            Icon(
              store.allStores
                  ? Icons.all_inbox_rounded
                  : selected
                      ? Icons.radio_button_checked
                      : Icons.storefront_outlined,
              size: 15,
              color:
                  selected ? const Color(0xFFC94C6E) : const Color(0xFF8A8DA6),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                store.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFFD1D3E0),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addStoreButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: isAddingStore ? null : _showAddStoreDialog,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFC94C6E).withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: const Color(0xFFC94C6E).withValues(alpha: 0.34),
          ),
        ),
        child: Row(
          children: [
            if (isAddingStore)
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.add_business_rounded,
                size: 16,
                color: Color(0xFFC94C6E),
              ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '매장 추가',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
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
              _sidebarBrandHeader(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              ),
              _storeAccordion(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
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
              displayStore,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFB5B8C9),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          if (canUseCustomerDb(widget.role))
            IconButton(
              tooltip: '오늘 알림',
              onPressed:
                  isPlanAlertLoading ? null : () => _openTodayPlanAlert(),
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.event_available_rounded),
                  if (todayPlanAlert?.entries.isNotEmpty == true)
                    const Positioned(
                      right: -1,
                      top: -1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xFFC94C6E),
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox(width: 8, height: 8),
                      ),
                    ),
                ],
              ),
            ),
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
                  _sidebarBrandHeader(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  ),
                  _storeAccordion(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
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

class _StoreOption {
  final String id;
  final String name;
  final String normalizedName;
  final bool isActive;
  final bool allStores;

  const _StoreOption({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.isActive,
    required this.allStores,
  });

  const _StoreOption.all()
      : id = '',
        name = '전체 매장',
        normalizedName = '',
        isActive = true,
        allStores = true;

  factory _StoreOption.fromMap(Map<String, dynamic> data) {
    final name = normalizeStoreName(data['name'] ?? data['normalized_name']);
    return _StoreOption(
      id: data['id']?.toString() ?? '',
      name: name,
      normalizedName: normalizeStoreName(data['normalized_name'] ?? name),
      isActive: data['is_active'] != false,
      allStores: false,
    );
  }
}
