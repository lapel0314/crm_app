import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/services/data_quality_service.dart';
import 'package:crm_app/utils/store_utils.dart';

final supabase = Supabase.instance.client;

class DataQualityPage extends StatefulWidget {
  final String role;
  final String currentStore;

  const DataQualityPage({
    super.key,
    required this.role,
    required this.currentStore,
  });

  @override
  State<DataQualityPage> createState() => _DataQualityPageState();
}

class _DataQualityPageState extends State<DataQualityPage> {
  final service = DataQualityService(supabase);
  final searchController = TextEditingController();
  List<DataQualityIssue> issues = [];
  bool isLoading = true;
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
      final scopedRows = rows.where((row) {
        return includesStoreForRole(
          role: widget.role,
          currentStore: widget.currentStore,
          rowStore: row['store'],
        );
      }).toList();
      final nextIssues = service.analyzeCustomers(scopedRows);
      if (!mounted) return;
      setState(() {
        issues = nextIssues;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('data quality load failed: $e');
      if (!mounted) return;
      setState(() => isLoading = false);
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
    return issues.where((issue) {
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

  int _count(String type) {
    if (type == '전체') return issues.length;
    return issues.where((issue) => _typeLabel(issue.type) == type).length;
  }

  Color _severityColor(String severity) {
    return severity == '높음' ? const Color(0xFFDC2626) : const Color(0xFFD97706);
  }

  Widget _summaryTile(String label, int count, IconData icon) {
    return Expanded(
      child: Container(
        height: 88,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF111827)),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$count건',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isAdmin) {
      return const Scaffold(body: Center(child: Text('접근 권한 없음')));
    }

    final rows = filteredIssues;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '데이터 품질 검사',
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
                  ),
                ),
                SizedBox(
                  width: 320,
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
                ),
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
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _summaryTile('전체 이슈', issues.length, Icons.fact_check),
                const SizedBox(width: 12),
                _summaryTile('중복 의심', _count('중복'), Icons.group),
                const SizedBox(width: 12),
                _summaryTile('전화번호', _count('전화번호'), Icons.phone),
                const SizedBox(width: 12),
                _summaryTile(
                    '가입일/통신사', _count('가입일') + _count('통신사'), Icons.event_note),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (final type in issueTypes)
                  ChoiceChip(
                    label: Text('$type ${_count(type)}'),
                    selected: selectedType == type,
                    onSelected: (_) => setState(() => selectedType = type),
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
                        ? const Center(child: Text('조건에 맞는 품질 이슈가 없습니다'))
                        : ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (_, index) => _issueRow(rows[index]),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
