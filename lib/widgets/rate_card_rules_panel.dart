import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:crm_app/services/rate_card_service.dart';

class RateCardRulesPanel extends StatefulWidget {
  final String carrier;
  final ValueChanged<String> onMessage;

  const RateCardRulesPanel({
    super.key,
    required this.carrier,
    required this.onMessage,
  });

  @override
  State<RateCardRulesPanel> createState() => RateCardRulesPanelState();
}

class RateCardRulesPanelState extends State<RateCardRulesPanel> {
  late final RateCardService service;
  final searchController = TextEditingController();
  final moneyFormat = NumberFormat('#,###');
  List<RateCardRule> rules = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    service = RateCardService(Supabase.instance.client);
    fetchRules();
  }

  @override
  void didUpdateWidget(covariant RateCardRulesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.carrier != widget.carrier) {
      fetchRules();
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> fetchRules() async {
    setState(() => isLoading = true);
    try {
      final data = await service.fetchRules(
        keyword: searchController.text,
        carrier: widget.carrier,
      );
      if (!mounted) return;
      setState(() {
        rules = data;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('rate card load failed: $e');
      if (!mounted) return;
      setState(() => isLoading = false);
      widget.onMessage('단가표를 불러오지 못했습니다.');
    }
  }

  int parseMoney(String value) {
    return int.tryParse(value.replaceAll(',', '').trim()) ?? 0;
  }

  String money(int value) => moneyFormat.format(value);

  void applyMoneyFormat(TextEditingController controller, String value) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9-]'), '');
    if (cleaned.isEmpty || cleaned == '-') {
      controller.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
      return;
    }
    final number = int.tryParse(cleaned) ?? 0;
    final formatted = moneyFormat.format(number);
    controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  void showRuleDialog([RateCardRule? rule]) {
    var carrier =
        rule?.carrier.isNotEmpty == true ? rule!.carrier : widget.carrier;
    final modelController = TextEditingController(text: rule?.modelName ?? '');
    final planController = TextEditingController(text: rule?.planName ?? '');
    final addServiceController =
        TextEditingController(text: rule?.addServiceName ?? '');
    final baseRebateController =
        TextEditingController(text: rule == null ? '' : money(rule.baseRebate));
    final addRebateController =
        TextEditingController(text: rule == null ? '' : money(rule.addRebate));
    final deductionController =
        TextEditingController(text: rule == null ? '' : money(rule.deduction));
    final memoController = TextEditingController(text: rule?.memo ?? '');
    var joinType = rule?.joinType ?? '';
    var contractType = rule?.contractType ?? '';
    var isActive = rule?.isActive ?? true;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final planItems = officialPlanCandidates[carrier] ?? const <String>[];
          return AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: Text(
              rule == null ? '단가 등록' : '단가 수정',
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
            content: SizedBox(
              width: 760,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _dropdown<String>(
                      label: '통신사',
                      value: carrier,
                      items: const ['SKT', 'KT', 'LG'],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => carrier = value);
                      },
                    ),
                    _autocomplete(
                      label: '모델명',
                      controller: modelController,
                      options: samsungAppleModels2024Plus,
                    ),
                    _autocomplete(
                      label: '요금제',
                      controller: planController,
                      options: planItems,
                    ),
                    _dropdown<String>(
                      label: '가입유형',
                      value: joinType,
                      items: const ['', '신규', '번호이동', '기변'],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => joinType = value);
                        }
                      },
                    ),
                    _dropdown<String>(
                      label: '공시/선약',
                      value: contractType,
                      items: const ['', '공시', '선약'],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => contractType = value);
                        }
                      },
                    ),
                    _input('부가서비스', addServiceController),
                    _input(
                      '리베이트',
                      baseRebateController,
                      keyboardType: TextInputType.number,
                      onChanged: (value) =>
                          applyMoneyFormat(baseRebateController, value),
                    ),
                    _input(
                      '부가리베이트',
                      addRebateController,
                      keyboardType: TextInputType.number,
                      onChanged: (value) =>
                          applyMoneyFormat(addRebateController, value),
                    ),
                    _input(
                      '차감항목',
                      deductionController,
                      keyboardType: TextInputType.number,
                      onChanged: (value) =>
                          applyMoneyFormat(deductionController, value),
                    ),
                    SizedBox(
                      width: 492,
                      child: _input('메모', memoController, maxLines: 3),
                    ),
                    SizedBox(
                      width: 240,
                      child: SwitchListTile(
                        value: isActive,
                        title: const Text('사용'),
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: const Color(0xFFC94C6E),
                        onChanged: (value) {
                          setDialogState(() => isActive = value);
                        },
                      ),
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
              ElevatedButton(
                style: _primaryButtonStyle(),
                onPressed: () async {
                  if (modelController.text.trim().isEmpty ||
                      planController.text.trim().isEmpty) {
                    widget.onMessage('모델명과 요금제는 필수입니다.');
                    return;
                  }
                  final values = {
                    'carrier': carrier,
                    'model_name': modelController.text,
                    'plan_name': planController.text,
                    'join_type': joinType,
                    'contract_type': contractType,
                    'add_service_name': addServiceController.text,
                    'base_rebate': parseMoney(baseRebateController.text),
                    'add_rebate': parseMoney(addRebateController.text),
                    'deduction': parseMoney(deductionController.text),
                    'memo': memoController.text,
                    'is_active': isActive,
                  };
                  try {
                    if (rule == null) {
                      await service.createRule(values);
                    } else {
                      await service.updateRule(rule.id, values);
                    }
                    if (!mounted) return;
                    Navigator.pop(context);
                    widget.onMessage(rule == null ? '단가 등록 완료' : '단가 수정 완료');
                    await fetchRules();
                  } catch (e) {
                    debugPrint('rate card save failed: $e');
                    widget.onMessage('단가 저장에 실패했습니다.');
                  }
                },
                child: const Text('저장'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> showGoogleSheetLinkDialog() async {
    final controllers = {
      'SKT': TextEditingController(),
      'KT': TextEditingController(),
      'LG': TextEditingController(),
    };
    var isLoadingUrl = true;
    var dialogSaving = false;
    var dialogClosed = false;

    try {
      final urls = await service.fetchGoogleSheetCsvUrls();
      for (final entry in controllers.entries) {
        entry.value.text = urls[entry.key] ?? '';
      }
    } catch (e) {
      debugPrint('rate card source load failed: $e');
      widget.onMessage('구글시트 링크를 불러오지 못했습니다.');
    } finally {
      isLoadingUrl = false;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> save() async {
            setDialogState(() => dialogSaving = true);
            try {
              await service.saveGoogleSheetCsvUrls(
                controllers.map(
                  (carrier, controller) => MapEntry(
                    carrier,
                    controller.text,
                  ),
                ),
              );
              if (!mounted) return;
              setDialogState(() => dialogSaving = false);
              dialogClosed = true;
              Navigator.pop(context);
              widget.onMessage('구글시트 링크 저장 완료');
            } on FormatException catch (e) {
              widget.onMessage(e.message);
            } catch (e) {
              debugPrint('rate card source save failed: $e');
              widget.onMessage('구글시트 링크 저장에 실패했습니다.');
            } finally {
              if (mounted && !dialogClosed) {
                setDialogState(() => dialogSaving = false);
              }
            }
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: Text(
              '단가 등록',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            content: SizedBox(
              width: 680,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final carrier in const ['SKT', 'KT', 'LG']) ...[
                    _sheetLinkInput(
                      carrier: carrier,
                      controller: controllers[carrier]!,
                      enabled: !isLoadingUrl && !dialogSaving,
                      onChanged: () => setDialogState(() {}),
                    ),
                    if (carrier != 'LG') const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'CSV 헤더: carrier, model_name, plan_name, join_type, contract_type, add_service_name, base_rebate, add_rebate, deduction, is_active',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: dialogSaving ? null : () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              ElevatedButton(
                style: _primaryButtonStyle(),
                onPressed: dialogSaving ? null : save,
                child: Text(dialogSaving ? '저장 중' : '저장'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sheetLinkInput({
    required String carrier,
    required TextEditingController controller,
    required bool enabled,
    required VoidCallback onChanged,
  }) {
    final hasLink = controller.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              carrier,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color:
                    hasLink ? const Color(0xFFEFF6FF) : const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                hasLink ? '등록됨' : '미등록',
                style: TextStyle(
                  color: hasLink
                      ? const Color(0xFF2563EB)
                      : const Color(0xFFE11D48),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          maxLines: 2,
          decoration: _inputDecoration(
            'https://docs.google.com/spreadsheets/...',
          ),
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }

  Widget _autocomplete({
    required String label,
    required TextEditingController controller,
    required List<String> options,
  }) {
    return SizedBox(
      width: 240,
      child: RawAutocomplete<String>(
        textEditingController: controller,
        focusNode: FocusNode(),
        optionsBuilder: (value) {
          final text = value.text.trim().toLowerCase();
          if (text.isEmpty) return options;
          return options.where((option) => option.toLowerCase().contains(text));
        },
        fieldViewBuilder: (context, textController, focusNode, onSubmitted) {
          return TextField(
            controller: textController,
            focusNode: focusNode,
            decoration: _inputDecoration(label),
            onSubmitted: (_) => onSubmitted(),
          );
        },
        optionsViewBuilder: (context, onSelected, values) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              child: SizedBox(
                width: 240,
                height: 220,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: values
                      .map(
                        (value) => ListTile(
                          dense: true,
                          title: Text(value),
                          onTap: () => onSelected(value),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _input(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) {
    return SizedBox(
      width: 240,
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        onChanged: onChanged,
        decoration: _inputDecoration(label),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: 240,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: _inputDecoration(label),
        items: items
            .map(
              (item) => DropdownMenuItem<T>(
                value: item,
                child: Text(item.toString().isEmpty ? '전체' : item.toString()),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
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
        borderSide: const BorderSide(color: Color(0xFFC94C6E), width: 1.4),
      ),
    );
  }

  ButtonStyle _primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFFC94C6E),
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: showGoogleSheetLinkDialog,
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('단가 등록'),
      style: _headerButtonStyle(),
    );
  }

  ButtonStyle _headerButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF374151),
      elevation: 0,
      side: const BorderSide(color: Color(0xFFE8E9EF)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    );
  }
}
