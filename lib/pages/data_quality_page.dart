import 'package:flutter/material.dart';
import 'package:crm_app/theme/app_theme.dart';
import 'package:crm_app/widgets/empty_state.dart';
import 'package:crm_app/widgets/app_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/services/data_quality_service.dart';
import 'package:crm_app/utils/store_utils.dart';

final supabase = Supabase.instance.client;

typedef CustomerIssueOpenHandler = void Function({
  required String name,
  required String phone,
});

class DataQualityPage extends StatefulWidget {
  final String role;
  final String currentStore;
  final CustomerIssueOpenHandler? onOpenCustomer;

  const DataQualityPage({
    super.key,
    required this.role,
    required this.currentStore,
    this.onOpenCustomer,
  });

  @override
  State<DataQualityPage> createState() => _DataQualityPageState();
}

class _DataQualityPageState extends State<DataQualityPage> {
  final service = DataQualityService(supabase);
  final searchController = TextEditingController();
  List<DataQualityIssue> issues = [];
  List<DataQualityIssue> dismissedIssues = [];
  bool isLoading = true;
  bool showDismissed = false;
  String selectedType = '전체';

  bool get isAdmin => isPrivilegedRole(widget.role);

  @override
  void initState() {
    super.initState();
    fetchIssues();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> fetchIssues() async {
    if (!isAdmin) {
      setState(() => isLoading = false);
      return;
    }

    setState(() => isLoading = true);
    try {
      final rows = await service.fetchCustomers();
      final dismissals = await service.fetchDismissals();
      final scopedRows = rows.where((row) {
        return includesStoreForRole(
          role: widget.role,
          currentStore: widget.currentStore,
          rowStore: row['store'],
        );
      }).toList();
      final analysis =
          service.analyzeCustomers(scopedRows, dismissals: dismissals);
      if (!mounted) return;
      setState(() {
        issues = analysis.active;
        dismissedIssues = analysis.dismissed;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('data quality load failed: $e');
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<void> _dismissIssue(DataQualityIssue issue) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: Colors.white,
            title: const Text(
              '이슈 무시',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            content: Text(
              issue.type == 'duplicate'
                  ? '${issue.phone} 번호의 중복(${issue.memberCount ?? 0}건)을 확인 완료로 처리할까요?\n같은 번호의 중복 이슈가 모두 숨겨지며, 새 중복이 추가되면 다시 표시됩니다.'
                  : '${issue.name} 고객의 "${issue.title}" 이슈를 확인 완료로 처리할까요?\n해당 값이 수정되면 다시 검사됩니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF111827),
                  foregroundColor: Colors.white,
                ),
                child: const Text('무시'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    try {
      await service.dismissIssue(issue);
      await fetchIssues();
    } catch (e) {
      debugPrint('dismiss failed: $e');
      if (!mounted) return;
      showToast(context, '무시 처리에 실패했습니다. 다시 시도해 주세요.', error: true);
    }
  }

  Future<void> _restoreIssue(DataQualityIssue issue) async {
    try {
      await service.restoreIssue(issue);
      await fetchIssues();
    } catch (e) {
      debugPrint('restore failed: $e');
      if (!mounted) return;
      showToast(context, '해제에 실패했습니다. 다시 시도해 주세요.', error: true);
    }
  }

  List<String> get issueTypes => [
        '전체',
        '중복',
        '전화번호',
        '가입일',
        '통신사',
      ];

  String _typeLabel(String type) {
    return switch (type) {
      'duplicate' => '중복',
      'phone' => '전화번호',
      'join_date' => '가입일',
      'carrier' => '통신사',
      _ => type,
    };
  }

  List<DataQualityIssue> get filteredIssues {
    final query = searchController.text.trim().toLowerCase();
    final source = showDismissed ? dismissedIssues : issues;
    return source.where((issue) {
      final matchesType =
          selectedType == '전체' || _typeLabel(issue.type) == selectedType;
      if (!matchesType) return false;
      if (query.isEmpty) return true;
      final haystack = [
        issue.title,
        issue.name,
        issue.phone,
        issue.store,
        issue.joinDate,
        issue.carrier,
        issue.previousCarrier,
        issue.detail,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  // 필터 칩용 — 현재 보고 있는 목록(활성/무시됨) 기준.
  int _count(String type) {
    final source = showDismissed ? dismissedIssues : issues;
    if (type == '전체') return source.length;
    return source.where((issue) => _typeLabel(issue.type) == type).length;
  }

  // 요약 타일용 — 무시됨 보기와 무관하게 활성 이슈 기준.
  int _activeCount(String type) {
    if (type == '전체') return issues.length;
    return issues.where((issue) => _typeLabel(issue.type) == type).length;
  }

  Color _severityColor(String severity) {
    return severity == '높음' ? const Color(0xFFDC2626) : const Color(0xFFD97706);
  }

  void _openCustomer(DataQualityIssue issue) {
    widget.onOpenCustomer?.call(
      name: issue.name == '-' ? '' : issue.name,
      phone: issue.phone == '-' ? '' : issue.phone,
    );
  }

  Widget _summaryTile(
    String label,
    int count,
    IconData icon, {
    bool expand = true,
    bool compact = false,
  }) {
    final tile = Container(
      height: compact ? 70 : 88,
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 30 : 36,
            height: compact ? 30 : 36,
            decoration: BoxDecoration(
              color: AppTheme.primaryTint,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.primaryTintStrong),
            ),
            child: Icon(
              icon,
              color: AppTheme.primary,
              size: compact ? 17 : 21,
            ),
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$count건',
                  style: TextStyle(
                    fontSize: compact ? 18 : 22,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF111827),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return expand ? Expanded(child: tile) : tile;
  }

  Widget _issueRow(DataQualityIssue issue) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F3F5))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              _typeLabel(issue.type),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              issue.severity,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: _severityColor(issue.severity),
              ),
            ),
          ),
          SizedBox(
            width: 210,
            child: Text(
              '${issue.name}\n${issue.phone}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            width: 150,
            child: Text(
              issue.store,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 210,
            child: Text(
              '가입일 ${issue.joinDate}\n${issue.carrier} / ${issue.previousCarrier}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${issue.title} - ${issue.detail}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: Color(0xFF374151),
              ),
            ),
          ),
          IconButton(
            onPressed: widget.onOpenCustomer == null
                ? null
                : () => _openCustomer(issue),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            tooltip: '고객DB에서 보기',
          ),
          showDismissed
              ? IconButton(
                  onPressed: () => _restoreIssue(issue),
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  tooltip: '무시 해제',
                )
              : IconButton(
                  onPressed: () => _dismissIssue(issue),
                  icon: const Icon(Icons.visibility_off_outlined, size: 18),
                  tooltip: '확인 완료(무시)',
                ),
        ],
      ),
    );
  }

  Widget _issueCard(DataQualityIssue issue) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E9EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IssuePill(label: _typeLabel(issue.type)),
              const SizedBox(width: 8),
              Text(
                issue.severity,
                style: TextStyle(
                  color: _severityColor(issue.severity),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: widget.onOpenCustomer == null
                    ? null
                    : () => _openCustomer(issue),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                tooltip: '고객DB에서 보기',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
              showDismissed
                  ? IconButton(
                      onPressed: () => _restoreIssue(issue),
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      tooltip: '무시 해제',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                    )
                  : IconButton(
                      onPressed: () => _dismissIssue(issue),
                      icon: const Icon(Icons.visibility_off_outlined, size: 18),
                      tooltip: '확인 완료(무시)',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                    ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            issue.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${issue.name} · ${issue.phone}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${issue.store} · 가입일 ${issue.joinDate} · ${issue.carrier} / ${issue.previousCarrier}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            issue.detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: searchController,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: '고객, 연락처, 매장 검색',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _titleBlock() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '고객정리',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
        SizedBox(height: 4),
        Text(
          '중복 고객, 전화번호, 가입일, 통신사 이상값을 점검합니다',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6B7280),
          ),
        ),
      ],
    );
  }

  Widget _header(bool mobile) {
    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titleBlock(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _searchField()),
              const SizedBox(width: 8),
              SizedBox(
                width: 42,
                height: 42,
                child: ElevatedButton(
                  onPressed: fetchIssues,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111827),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Icon(Icons.refresh_rounded, size: 18),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: _titleBlock()),
        const SizedBox(width: 16),
        SizedBox(width: 320, child: _searchField()),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: fetchIssues,
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('새로고침'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF111827),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        ),
      ],
    );
  }

  Widget _summarySection(bool mobile) {
    if (mobile) {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.25,
        children: [
          _summaryTile('전체 이슈', issues.length, Icons.storefront_rounded,
              expand: false, compact: true),
          _summaryTile('중복 의심', _activeCount('중복'), Icons.contact_phone_rounded,
              expand: false, compact: true),
          _summaryTile(
              '전화번호', _activeCount('전화번호'), Icons.phone_android_rounded,
              expand: false, compact: true),
          _summaryTile(
            '가입일/통신사',
            _activeCount('가입일') + _activeCount('통신사'),
            Icons.sim_card_rounded,
            expand: false,
            compact: true,
          ),
        ],
      );
    }

    return Row(
      children: [
        _summaryTile('전체 이슈', issues.length, Icons.storefront_rounded),
        const SizedBox(width: 12),
        _summaryTile('중복 의심', _activeCount('중복'), Icons.contact_phone_rounded),
        const SizedBox(width: 12),
        _summaryTile('전화번호', _activeCount('전화번호'), Icons.phone_android_rounded),
        const SizedBox(width: 12),
        _summaryTile(
          '가입일/통신사',
          _activeCount('가입일') + _activeCount('통신사'),
          Icons.sim_card_rounded,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isAdmin) {
      return const Scaffold(body: Center(child: Text('접근 권한 없음')));
    }

    final rows = filteredIssues;
    final mobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: Padding(
        padding: EdgeInsets.all(mobile ? 18 : 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(mobile),
            const SizedBox(height: 18),
            _summarySection(mobile),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in issueTypes)
                  ChoiceChip(
                    label: Text('$type ${_count(type)}'),
                    selected: selectedType == type,
                    onSelected: (_) => setState(() => selectedType = type),
                  ),
                FilterChip(
                  label: Text('무시됨 ${dismissedIssues.length}'),
                  selected: showDismissed,
                  onSelected: (value) =>
                      setState(() => showDismissed = value),
                  selectedColor: const Color(0xFFE5E7EB),
                  checkmarkColor: const Color(0xFF374151),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : rows.isEmpty
                        ? EmptyState(
                            icon: Icons.task_alt_rounded,
                            title: showDismissed
                                ? '무시 처리된 이슈가 없습니다'
                                : '조건에 맞는 품질 이슈가 없습니다',
                            subtitle: showDismissed
                                ? '이슈를 무시 처리하면 여기에 모입니다'
                                : '데이터가 깨끗하거나 필터에 걸린 이슈가 없습니다',
                          )
                        : ListView.builder(
                            padding: EdgeInsets.only(bottom: mobile ? 10 : 0),
                            itemCount: rows.length,
                            itemBuilder: (_, index) => mobile
                                ? _issueCard(rows[index])
                                : _issueRow(rows[index]),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IssuePill extends StatelessWidget {
  final String label;

  const _IssuePill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primaryTint,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.primaryTintStrong),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
