import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/utils/debouncer.dart';
import 'package:crm_app/utils/phone_utils.dart';
import 'package:crm_app/utils/postgrest_filter_utils.dart';
import 'package:crm_app/utils/store_utils.dart';
import 'package:crm_app/utils/supabase_fetch_utils.dart';
import 'package:crm_app/widgets/list_pagination.dart';

/// 사전예약 고객 관리 화면 (가망고객 페이지에서 진입).
class PreReservationPage extends StatefulWidget {
  final String role;
  final String currentStore;

  const PreReservationPage({
    super.key,
    required this.role,
    required this.currentStore,
  });

  @override
  State<PreReservationPage> createState() => _PreReservationPageState();
}

class _PreReservationPageState extends State<PreReservationPage> {
  static const statusOptions = ['대기', '완료', '취소'];
  static const subsidyOptions = ['공시', '선약'];

  final supabase = Supabase.instance.client;
  final searchController = TextEditingController();
  final Debouncer _searchDebouncer =
      Debouncer(const Duration(milliseconds: 250));

  List<Map<String, dynamic>> reservations = [];
  bool isLoading = true;
  String statusFilter = '전체';
  int currentPage = 0;
  static const int pageSize = 20;

  bool get canView => canUseLeads(widget.role);
  bool get canDelete => canDeleteLead(widget.role);

  @override
  void initState() {
    super.initState();
    fetchReservations();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> fetchReservations({bool silent = false}) async {
    setState(() => isLoading = true);
    final keyword = searchController.text.trim();
    try {
      final List<dynamic> data = keyword.isEmpty
          ? await fetchAllRows(() => supabase
              .from('pre_reservations')
              .select()
              .eq('is_deleted', false)
              .order('receive_date', ascending: true)
              .order('created_at', ascending: true))
          : await fetchAllRows(() => supabase
              .from('pre_reservations')
              .select()
              .eq('is_deleted', false)
              .or(postgrestIlikeAnyFilter(
                const [
                  'customer_name',
                  'phone',
                  'carrier',
                  'subsidy_type',
                  'reserved_model',
                  'reserved_color',
                  'reservation_number',
                ],
                keyword,
              ))
              .order('receive_date', ascending: true)
              .order('created_at', ascending: true));

      final next = data
          .map((e) => Map<String, dynamic>.from(e))
          .where(
            (row) => includesStoreForRole(
              role: widget.role,
              currentStore: widget.currentStore,
              rowStore: row['store'],
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        reservations = next;
        currentPage = 0;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('pre reservation load failed: $e');
      if (!mounted) return;
      setState(() {
        reservations = [];
        isLoading = false;
      });
      if (!silent) _showMessage('사전예약 조회에 실패했습니다.');
    }
  }

  List<Map<String, dynamic>> get filteredReservations {
    if (statusFilter == '전체') return reservations;
    return reservations
        .where((row) => _text(row['status']) == statusFilter)
        .toList();
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  Future<void> _saveReservation({
    String? id,
    required Map<String, dynamic> payload,
  }) async {
    if (_text(payload['customer_name']).isEmpty) {
      _showMessage('고객명은 필수입니다.');
      return;
    }
    final phone = _text(payload['phone']);
    if (phone.isNotEmpty && !isValidKoreanMobilePhoneNumber(phone)) {
      _showMessage('휴대폰번호 형식은 010-1234-1234 입니다.');
      return;
    }

    try {
      if (id == null) {
        await supabase.from('pre_reservations').insert({
          ...payload,
          'store': normalizeStoreName(widget.currentStore),
          'created_by': supabase.auth.currentUser?.id,
        });
      } else {
        await supabase.from('pre_reservations').update(payload).eq('id', id);
      }
      if (mounted) Navigator.pop(context);
      _showMessage(id == null ? '사전예약 등록 완료' : '사전예약 수정 완료');
      fetchReservations(silent: true);
    } catch (e) {
      debugPrint('pre reservation save failed: $e');
      _showMessage('저장에 실패했습니다. 다시 시도해 주세요.');
    }
  }

  Future<void> _updateStatus(Map<String, dynamic> row, String status) async {
    try {
      await supabase
          .from('pre_reservations')
          .update({'status': status}).eq('id', row['id']);
      if (!mounted) return;
      setState(() => row['status'] = status);
    } catch (e) {
      debugPrint('pre reservation status update failed: $e');
      _showMessage('상태 변경에 실패했습니다.');
    }
  }

  Future<void> _deleteReservation(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: Colors.white,
            title: const Text(
              '사전예약 삭제',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            content: Text('${_text(row['customer_name'])} 고객의 사전예약을 삭제할까요?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                ),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    try {
      await supabase.from('pre_reservations').update({
        'is_deleted': true,
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'deleted_by': supabase.auth.currentUser?.id,
      }).eq('id', row['id']);
      _showMessage('사전예약 삭제 완료');
      fetchReservations(silent: true);
    } catch (e) {
      debugPrint('pre reservation delete failed: $e');
      _showMessage('삭제에 실패했습니다.');
    }
  }

  InputDecoration _dialogInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFFAFAFC),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
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
        borderSide: const BorderSide(color: Color(0xFF6B7280), width: 1.4),
      ),
    );
  }

  Future<void> _openEditor({Map<String, dynamic>? row}) async {
    final nameController =
        TextEditingController(text: _text(row?['customer_name']));
    final phoneController = TextEditingController(text: _text(row?['phone']));
    final carrierController =
        TextEditingController(text: _text(row?['carrier']));
    final modelController =
        TextEditingController(text: _text(row?['reserved_model']));
    final colorController =
        TextEditingController(text: _text(row?['reserved_color']));
    final numberController =
        TextEditingController(text: _text(row?['reservation_number']));
    String subsidyType = subsidyOptions.contains(_text(row?['subsidy_type']))
        ? _text(row?['subsidy_type'])
        : '';
    String status = statusOptions.contains(_text(row?['status']))
        ? _text(row?['status'])
        : '대기';
    bool idScanned = row?['id_scanned'] == true;
    DateTime? receiveDate =
        DateTime.tryParse(_text(row?['receive_date']));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Widget input(String label, TextEditingController controller,
                {ValueChanged<String>? onChanged}) {
              return SizedBox(
                width: 240,
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: _dialogInputDecoration(label),
                ),
              );
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              title: Text(
                row == null ? '사전예약 등록' : '사전예약 수정',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              content: SizedBox(
                width: 512,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      input('고객명', nameController),
                      input(
                        '핸드폰번호',
                        phoneController,
                        onChanged: (value) {
                          final formatted = formatPartialPhoneNumber(value);
                          if (formatted != value) {
                            phoneController.value = TextEditingValue(
                              text: formatted,
                              selection: TextSelection.collapsed(
                                offset: formatted.length,
                              ),
                            );
                          }
                        },
                      ),
                      input('통신사', carrierController),
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<String>(
                          initialValue: subsidyType.isEmpty ? null : subsidyType,
                          decoration: _dialogInputDecoration('공시/선약'),
                          items: [
                            for (final option in subsidyOptions)
                              DropdownMenuItem(
                                value: option,
                                child: Text(option),
                              ),
                          ],
                          onChanged: (value) => setDialogState(
                              () => subsidyType = value ?? ''),
                        ),
                      ),
                      input('예약기종', modelController),
                      input('색상', colorController),
                      input('예약번호', numberController),
                      SizedBox(
                        width: 240,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate: receiveDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setDialogState(() => receiveDate = picked);
                            }
                          },
                          icon: const Icon(Icons.event_rounded, size: 17),
                          label: Text(
                            receiveDate == null
                                ? '받으실 날짜 선택'
                                : '받으실 날짜: ${receiveDate!.toIso8601String().substring(0, 10)}',
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 46),
                            alignment: Alignment.centerLeft,
                            foregroundColor: const Color(0xFF374151),
                            side: const BorderSide(color: Color(0xFFE8E9EF)),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<String>(
                          initialValue: status,
                          decoration: _dialogInputDecoration('진행상태'),
                          items: [
                            for (final option in statusOptions)
                              DropdownMenuItem(
                                value: option,
                                child: Text(option),
                              ),
                          ],
                          onChanged: (value) =>
                              setDialogState(() => status = value ?? '대기'),
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: CheckboxListTile(
                          value: idScanned,
                          onChanged: (value) => setDialogState(
                              () => idScanned = value ?? false),
                          title: const Text(
                            '신분증 스캔 완료',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () => _saveReservation(
                    id: row == null ? null : _text(row['id']),
                    payload: {
                      'customer_name': nameController.text.trim(),
                      'phone': phoneController.text.trim(),
                      'carrier': carrierController.text.trim(),
                      'subsidy_type': subsidyType,
                      'reserved_model': modelController.text.trim(),
                      'reserved_color': colorController.text.trim(),
                      'reservation_number': numberController.text.trim(),
                      'receive_date':
                          receiveDate?.toIso8601String().substring(0, 10),
                      'id_scanned': idScanned,
                      'status': status,
                    },
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC94C6E),
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                  child: Text(row == null ? '등록' : '저장'),
                ),
              ],
            );
          },
        );
      },
    );
    // 컨트롤러는 의도적으로 dispose하지 않는다 — showDialog future가
    // 닫힘 애니메이션 도중 완료되어, 여기서 dispose하면 애니메이션 중
    // 리빌드되는 TextField가 disposed controller 에러를 낸다.
    // (leads_page 등 기존 다이얼로그들과 동일한 패턴)
  }

  Widget _segmentedFilter() {
    const options = ['전체', ...statusOptions];
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E9EF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((option) {
          final active = option == statusFilter;
          return InkWell(
            onTap: () => setState(() {
              statusFilter = option;
              currentPage = 0;
            }),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? const Color(0xFFC94C6E) : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                option,
                style: TextStyle(
                  color: active ? Colors.white : const Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _statusColor(String status) {
    return switch (status) {
      '완료' => const Color(0xFF16A34A),
      '취소' => const Color(0xFF9CA3AF),
      _ => const Color(0xFFD97706),
    };
  }

  Widget _statusDropdown(Map<String, dynamic> row) {
    final status =
        statusOptions.contains(_text(row['status'])) ? _text(row['status']) : '대기';
    return SizedBox(
      width: 86,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: status,
          isDense: true,
          borderRadius: BorderRadius.circular(8),
          style: TextStyle(
            color: _statusColor(status),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
          items: [
            for (final option in statusOptions)
              DropdownMenuItem(
                value: option,
                child: Text(
                  option,
                  style: TextStyle(
                    color: _statusColor(option),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null && value != status) _updateStatus(row, value);
          },
        ),
      ),
    );
  }

  Widget _idScanPill(bool scanned) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scanned ? const Color(0xFFDCFCE7) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        scanned ? 'O' : 'X',
        style: TextStyle(
          color:
              scanned ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _tableHeaderCell(String label, double width) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }

  Widget _desktopTable(List<Map<String, dynamic>> rows) {
    const widths = [96.0, 110.0, 128.0, 84.0, 84.0, 180.0, 120.0, 66.0, 96.0];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 1060),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFF1F3F5)),
                ),
              ),
              child: Row(
                children: [
                  _tableHeaderCell('받으실 날짜', widths[0]),
                  _tableHeaderCell('고객명', widths[1]),
                  _tableHeaderCell('번호', widths[2]),
                  _tableHeaderCell('통신사', widths[3]),
                  _tableHeaderCell('공시/선약', widths[4]),
                  _tableHeaderCell('예약기종/색상', widths[5]),
                  _tableHeaderCell('예약번호', widths[6]),
                  _tableHeaderCell('신분증', widths[7]),
                  _tableHeaderCell('진행상태', widths[8]),
                  const SizedBox(width: 76),
                ],
              ),
            ),
            for (final row in rows)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFF1F3F5)),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: widths[0],
                      child: Text(
                        _text(row['receive_date']).isEmpty
                            ? '-'
                            : _text(row['receive_date']),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: widths[1],
                      child: Text(
                        _text(row['customer_name']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    SizedBox(
                      width: widths[2],
                      child: Text(
                        _text(row['phone']).isEmpty ? '-' : _text(row['phone']),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    SizedBox(
                      width: widths[3],
                      child: Text(
                        _text(row['carrier']).isEmpty
                            ? '-'
                            : _text(row['carrier']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    SizedBox(
                      width: widths[4],
                      child: Text(
                        _text(row['subsidy_type']).isEmpty
                            ? '-'
                            : _text(row['subsidy_type']),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    SizedBox(
                      width: widths[5],
                      child: Text(
                        [
                          _text(row['reserved_model']),
                          _text(row['reserved_color']),
                        ].where((v) => v.isNotEmpty).join(' / '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    SizedBox(
                      width: widths[6],
                      child: Text(
                        _text(row['reservation_number']).isEmpty
                            ? '-'
                            : _text(row['reservation_number']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    SizedBox(
                      width: widths[7],
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _idScanPill(row['id_scanned'] == true),
                      ),
                    ),
                    SizedBox(
                      width: widths[8],
                      child: _statusDropdown(row),
                    ),
                    IconButton(
                      onPressed: () => _openEditor(row: row),
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      tooltip: '수정',
                      visualDensity: VisualDensity.compact,
                    ),
                    if (canDelete)
                      IconButton(
                        onPressed: () => _deleteReservation(row),
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 17),
                        tooltip: '삭제',
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mobileCard(Map<String, dynamic> row) {
    final modelColor = [
      _text(row['reserved_model']),
      _text(row['reserved_color']),
    ].where((v) => v.isNotEmpty).join(' / ');
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
              Expanded(
                child: Text(
                  _text(row['customer_name']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _statusDropdown(row),
              IconButton(
                onPressed: () => _openEditor(row: row),
                icon: const Icon(Icons.edit_outlined, size: 17),
                tooltip: '수정',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 30, height: 30),
              ),
              if (canDelete)
                IconButton(
                  onPressed: () => _deleteReservation(row),
                  icon: const Icon(Icons.delete_outline_rounded, size: 17),
                  tooltip: '삭제',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 30, height: 30),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_text(row['phone']).isEmpty ? '-' : _text(row['phone'])} · ${_text(row['carrier']).isEmpty ? '-' : _text(row['carrier'])} · ${_text(row['subsidy_type']).isEmpty ? '-' : _text(row['subsidy_type'])}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '기종 ${modelColor.isEmpty ? '-' : modelColor} · 예약번호 ${_text(row['reservation_number']).isEmpty ? '-' : _text(row['reservation_number'])}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '받으실 날짜 ${_text(row['receive_date']).isEmpty ? '-' : _text(row['receive_date'])}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '신분증',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(width: 4),
              _idScanPill(row['id_scanned'] == true),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!canView) {
      return const Scaffold(body: Center(child: Text('접근 권한 없음')));
    }

    final mobile = MediaQuery.of(context).size.width < 900;
    final rows = filteredReservations;
    final totalPages =
        rows.isEmpty ? 1 : ((rows.length - 1) ~/ pageSize) + 1;
    final safePage = currentPage.clamp(0, totalPages - 1);
    final visibleRows = rows
        .skip(safePage * pageSize)
        .take(pageSize)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      appBar: AppBar(
        title: const Text('사전예약'),
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
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: searchController,
                      onChanged: (_) => _searchDebouncer
                          .run(() => mounted ? fetchReservations() : null),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '고객명, 번호, 기종, 예약번호 검색',
                        prefixIcon: const Icon(
                          Icons.search,
                          size: 17,
                          color: Color(0xFF9CA3AF),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE8E9EF)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE8E9EF)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFC94C6E)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('예약 등록'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC94C6E),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: const Size(0, 38),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _segmentedFilter(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : visibleRows.isEmpty
                              ? const Center(child: Text('등록된 사전예약이 없습니다'))
                              : mobile
                                  ? ListView.builder(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      itemCount: visibleRows.length,
                                      itemBuilder: (_, index) =>
                                          _mobileCard(visibleRows[index]),
                                    )
                                  : SingleChildScrollView(
                                      child: _desktopTable(visibleRows),
                                    ),
                    ),
                    listPagination(
                      totalItems: rows.length,
                      safePage: safePage,
                      totalPages: totalPages,
                      onPageChanged: (page) =>
                          setState(() => currentPage = page),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
