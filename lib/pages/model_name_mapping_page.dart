import 'package:crm_app/utils/debouncer.dart';
import 'package:crm_app/utils/model_name_utils.dart';
import 'package:crm_app/utils/store_utils.dart';
import 'package:flutter/material.dart';
import 'package:crm_app/widgets/app_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ModelNameMappingPage extends StatefulWidget {
  final String role;

  const ModelNameMappingPage({super.key, required this.role});

  @override
  State<ModelNameMappingPage> createState() => _ModelNameMappingPageState();
}

class _ModelNameMappingPageState extends State<ModelNameMappingPage> {
  final supabase = Supabase.instance.client;
  final searchController = TextEditingController();
  final searchDebouncer = Debouncer(const Duration(milliseconds: 300));

  List<Map<String, dynamic>> mappings = [];
  bool isLoading = true;

  bool get canManage => isPrivilegedRole(widget.role);

  @override
  void initState() {
    super.initState();
    _fetchMappings();
  }

  @override
  void dispose() {
    searchDebouncer.dispose();
    searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchMappings() async {
    if (!canManage) {
      setState(() => isLoading = false);
      return;
    }

    setState(() => isLoading = true);
    try {
      final data = await supabase
          .from('model_name_mappings')
          .select()
          .order('display_name', ascending: true);
      if (!mounted) return;
      final rows = List<Map<String, dynamic>>.from(data);
      // 별칭 조인 문자열은 검색/렌더링마다 만들지 않고 1회만 계산해 둔다
      // (키 입력마다 전체 행을 재조인하던 프리징 원인).
      for (final mapping in rows) {
        final aliasesText = _aliasesText(mapping['registered_names']);
        mapping['_aliases_text'] = aliasesText;
        mapping['_search_text'] =
            '${mapping['display_name'] ?? ''} $aliasesText'.toLowerCase();
      }
      setState(() {
        mappings = rows;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showMessage('모델명 목록을 불러오지 못했습니다: $e');
    }
  }

  List<String> _parseAliases(String value) {
    final aliases = value
        .split(RegExp(r'[\n,]+'))
        .map((text) => text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
    final seen = <String>{};
    final result = <String>[];
    for (final alias in aliases) {
      final key = modelAliasKey(alias);
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      result.add(alias);
    }
    return result;
  }

  String _aliasesText(dynamic value) {
    final aliases = (value as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList();
    return aliases.join(', ');
  }

  List<Map<String, dynamic>> get filteredMappings {
    final query = searchController.text.trim().toLowerCase();
    if (query.isEmpty) return mappings;
    return mappings
        .where((mapping) =>
            (mapping['_search_text'] as String? ?? '').contains(query))
        .toList();
  }

  Future<void> _saveMapping({
    required String? id,
    required String displayName,
    required List<String> aliases,
    required bool isActive,
    required String memo,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    final payload = {
      'display_name': displayName,
      'registered_names': aliases,
      'is_active': isActive,
      'memo': memo.trim().isEmpty ? null : memo.trim(),
      'updated_by': userId,
    };

    if (id == null) {
      await supabase.from('model_name_mappings').insert({
        ...payload,
        'created_by': userId,
      });
    } else {
      await supabase.from('model_name_mappings').update(payload).eq('id', id);
    }
  }

  Future<void> _deleteMapping(Map<String, dynamic> mapping) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('모델명 매핑 삭제'),
        content: Text('${mapping['display_name']} 매핑을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await supabase.from('model_name_mappings').delete().eq(
            'id',
            mapping['id'],
          );
      await _fetchMappings();
      _showMessage('삭제했습니다.');
    } catch (e) {
      _showMessage('삭제 실패: $e');
    }
  }

  Future<void> _openEditor([Map<String, dynamic>? mapping]) async {
    final displayController = TextEditingController(
      text: mapping?['display_name']?.toString() ?? '',
    );
    final aliasesController = TextEditingController(
      text: _aliasesText(mapping?['registered_names']),
    );
    final memoController = TextEditingController(
      text: mapping?['memo']?.toString() ?? '',
    );
    var isActive = mapping?['is_active'] != false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(mapping == null ? '모델명 매핑 추가' : '모델명 매핑 수정'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: displayController,
                        decoration: const InputDecoration(
                          labelText: '표시될 모델명',
                          hintText: '예: 아이폰 17 256GB',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: aliasesController,
                        minLines: 4,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: '등록 모델명',
                          hintText: '예: IP-17, iphone17, 아이폰17',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: memoController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: '메모',
                          hintText: '선택 입력',
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: isActive,
                        onChanged: (value) {
                          setDialogState(() => isActive = value);
                        },
                        title: const Text('대시보드 집계에 사용'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () async {
                    final displayName = displayController.text.trim();
                    final aliases = _parseAliases(aliasesController.text);
                    if (displayName.isEmpty) {
                      _showMessage('표시될 모델명을 입력해 주세요.');
                      return;
                    }
                    if (aliases.isEmpty) {
                      _showMessage('등록 모델명을 하나 이상 입력해 주세요.');
                      return;
                    }

                    try {
                      await _saveMapping(
                        id: mapping?['id']?.toString(),
                        displayName: displayName,
                        aliases: aliases,
                        isActive: isActive,
                        memo: memoController.text,
                      );
                      if (!mounted) return;
                      Navigator.pop(context);
                      await _fetchMappings();
                      _showMessage('저장했습니다.');
                    } catch (e) {
                      _showMessage('저장 실패: $e');
                    }
                  },
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );

    displayController.dispose();
    aliasesController.dispose();
    memoController.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    showToast(context, message);
  }

  Widget _statusBadge(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFFF1F6) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isActive ? const Color(0xFFF9A8C7) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Text(
        isActive ? '사용' : '중지',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isActive ? const Color(0xFFC94C6E) : const Color(0xFF6B7280),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!canManage) {
      return const Scaffold(body: Center(child: Text('접근 권한 없음')));
    }

    final mobile = MediaQuery.of(context).size.width < 900;
    final rows = filteredMappings;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(
        title: const Text('모델명 관리'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
      ),
      body: Padding(
        padding: EdgeInsets.all(mobile ? 14 : 28),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: '표시 모델명, 등록 모델명 검색',
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onChanged: (_) => searchDebouncer
                        .run(() => mounted ? setState(() {}) : null),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('추가'),
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
                        ? const Center(child: Text('등록된 모델명 매핑이 없습니다'))
                        : ListView.separated(
                            itemCount: rows.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final row = rows[index];
                              final aliases =
                                  row['_aliases_text'] as String? ?? '';
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 10,
                                ),
                                title: Text(
                                  row['display_name']?.toString() ?? '-',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    aliases.isEmpty ? '-' : aliases,
                                    maxLines: mobile ? 3 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF6B7280),
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                                trailing: Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _statusBadge(row['is_active'] != false),
                                    IconButton(
                                      tooltip: '수정',
                                      icon: const Icon(Icons.edit_rounded),
                                      onPressed: () => _openEditor(row),
                                    ),
                                    IconButton(
                                      tooltip: '삭제',
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                      ),
                                      onPressed: () => _deleteMapping(row),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
