import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:crm_app/services/rebate_image_service.dart';
import 'package:crm_app/utils/store_utils.dart';

final supabase = Supabase.instance.client;

class RebatePage extends StatefulWidget {
  final String role;

  const RebatePage({super.key, required this.role});

  @override
  State<RebatePage> createState() => _RebatePageState();
}

class _RebatePageState extends State<RebatePage> {
  static const carriers = ['SKT', 'KT', 'LG'];
  late final RebateImageService service;
  DateTime selectedDate = DateTime.now();
  String selectedCarrier = 'SKT';
  RebateImage? currentImage;
  String? imageUrl;
  bool isLoading = true;
  bool isSaving = false;

  bool get canView => canViewRebate(widget.role);
  bool get canManage => isPrivilegedRole(widget.role);

  @override
  void initState() {
    super.initState();
    service = RebateImageService(supabase);
    _load();
  }

  Future<void> _load() async {
    if (!canView) {
      setState(() {
        isLoading = false;
        currentImage = null;
        imageUrl = null;
      });
      return;
    }

    setState(() {
      isLoading = true;
      imageUrl = null;
    });

    try {
      final image = await service.fetchByDate(selectedDate, selectedCarrier);
      final signedUrl =
          image == null ? null : await service.signedUrl(image.storagePath);

      if (!mounted) return;
      setState(() {
        currentImage = image;
        imageUrl = signedUrl;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('rebate image load failed: $e');
      if (!mounted) return;
      setState(() {
        currentImage = null;
        imageUrl = null;
        isLoading = false;
      });
      _showMessage('리베이트 이미지를 불러오지 못했습니다.');
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => _CompactMonthPicker(initialDate: selectedDate),
    );

    if (picked == null) return;
    setState(() {
      selectedDate = DateTime(picked.year, picked.month, picked.day);
    });
    await _load();
  }

  Widget _carrierTabs() {
    return Row(
      children: carriers.map((carrier) {
        final selected = selectedCarrier == carrier;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: InkWell(
            onTap: () async {
              setState(() {
                selectedCarrier = carrier;
              });
              await _load();
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 70,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFC94C6E) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? const Color(0xFFC94C6E)
                      : const Color(0xFFE8E9EF),
                ),
              ),
              child: Text(
                carrier,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF374151),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _uploadImage() async {
    if (!canManage || isSaving) return;

    final target = await _showUploadTargetDialog();
    if (target == null) return;

    const imageTypes = XTypeGroup(
      label: 'images',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
    );
    final file = await openFile(acceptedTypeGroups: const [imageTypes]);

    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      _showMessage('이미지 파일을 읽을 수 없습니다.');
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final previousImage =
          await service.fetchByDate(target.date, target.carrier);
      await service.saveImage(
        date: target.date,
        carrier: target.carrier,
        bytes: bytes,
        fileName: file.name,
        contentType: _contentType(file.name.split('.').last),
      );

      setState(() {
        selectedDate = DateTime(
          target.date.year,
          target.date.month,
          target.date.day,
        );
        selectedCarrier = target.carrier;
      });
      await _load();
      final actionText = previousImage == null ? '등록' : '수정';
      _showMessage('리베이트 이미지 $actionText 완료');
    } catch (e) {
      debugPrint('rebate image save failed: $e');
      _showMessage('이미지 저장에 실패했습니다.');
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Future<_RebateUploadTarget?> _showUploadTargetDialog() async {
    var uploadDate = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    var uploadCarrier = selectedCarrier;

    return showDialog<_RebateUploadTarget>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> pickDate() async {
            final picked = await showDialog<DateTime>(
              context: context,
              builder: (_) => _CompactMonthPicker(initialDate: uploadDate),
            );
            if (picked == null) return;
            setDialogState(() {
              uploadDate = DateTime(picked.year, picked.month, picked.day);
            });
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: const Text(
              '리베이트 이미지 업로드',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '통신사',
                    style: TextStyle(
                      color: Color(0xFF374151),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: carriers.map((carrier) {
                      final selected = uploadCarrier == carrier;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: () {
                              setDialogState(() {
                                uploadCarrier = carrier;
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFFC94C6E)
                                    : const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFFC94C6E)
                                      : const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Text(
                                carrier,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFF111827),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '날짜',
                    style: TextStyle(
                      color: Color(0xFF374151),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: pickDate,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_month_rounded,
                            color: Color(0xFFC94C6E),
                            size: 19,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _displayDate(uploadDate),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(
                  context,
                  _RebateUploadTarget(
                    carrier: uploadCarrier,
                    date: uploadDate,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC94C6E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('파일 선택'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final image = currentImage;
    if (!canManage || image == null || isSaving) return;

    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: const Text(
              '리베이트 이미지 삭제',
              style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Text('${_displayDate(selectedDate)} 이미지를 삭제하시겠습니까?'),
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
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldDelete) return;

    setState(() {
      isSaving = true;
    });

    try {
      await service.deleteImage(image);
      await _load();
      _showMessage('리베이트 이미지 삭제 완료');
    } catch (e) {
      debugPrint('rebate image delete failed: $e');
      _showMessage('이미지 삭제에 실패했습니다.');
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  String _contentType(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  String _displayDate(DateTime date) {
    return DateFormat('yyyy년 M월 d일', 'ko_KR').format(date);
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _headerActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool danger = false,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: danger ? const Color(0xFFDC2626) : Colors.white,
        foregroundColor: danger ? Colors.white : const Color(0xFF374151),
        elevation: 0,
        side: danger
            ? BorderSide.none
            : const BorderSide(color: Color(0xFFE8E9EF)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    );
  }

  Widget _datePanel() {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '날짜 선택',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE8E9EF)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_month_rounded,
                    color: Color(0xFFC94C6E),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _displayDate(selectedDate),
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageViewer() {
    return Expanded(
      child: Container(
        decoration: _cardDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE8E9EF))),
              ),
              child: Row(
                children: [
                  Text(
                    _displayDate(selectedDate),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                color: const Color(0xFFFAFAFC),
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : imageUrl == null
                        ? _emptyState()
                        : InkWell(
                            onTap: _openImageFullScreen,
                            child: InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 5,
                              child: Center(
                                child: Image.network(
                                  imageUrl!,
                                  fit: BoxFit.contain,
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  },
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Text('이미지를 표시할 수 없습니다.'),
                                  ),
                                ),
                              ),
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openImageFullScreen() {
    final url = imageUrl;
    if (url == null) return;

    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                constrained: false,
                minScale: 0.2,
                maxScale: 8,
                child: Image.network(
                  url,
                  fit: BoxFit.none,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text(
                      '이미지를 표시할 수 없습니다.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 18,
              right: 18,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mainPanel() {
    return _imageViewer();
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFC94C6E).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.image_not_supported_outlined,
              color: Color(0xFFC94C6E),
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '선택한 날짜에 등록된 이미지가 없습니다.',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            canManage ? '업로드 버튼으로 이미지를 등록하세요.' : '관리자가 이미지를 등록하면 표시됩니다.',
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFE8E9EF)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A000000),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!canView) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F5F8),
        body: Center(child: Text('접근 권한이 없습니다.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '리베이트',
                        style: TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _carrierTabs(),
                    ],
                  ),
                ),
                _headerActionButton(
                  icon: Icons.calendar_month_outlined,
                  label: '날짜 선택',
                  onTap: _pickDate,
                ),
                if (canManage) ...[
                  const SizedBox(width: 10),
                  _headerActionButton(
                    icon: currentImage == null
                        ? Icons.upload_file_rounded
                        : Icons.change_circle_outlined,
                    label: currentImage == null ? '업로드' : '수정',
                    onTap: isSaving ? null : _uploadImage,
                  ),
                  if (currentImage != null) ...[
                    const SizedBox(width: 10),
                    _headerActionButton(
                      icon: Icons.delete_outline,
                      label: '삭제',
                      onTap: isSaving ? null : _confirmDelete,
                      danger: true,
                    ),
                  ],
                ],
                const SizedBox(width: 10),
                _headerActionButton(
                  icon: Icons.refresh_rounded,
                  label: '새로고침',
                  onTap: isSaving ? null : _load,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _datePanel(),
                  const SizedBox(width: 18),
                  _mainPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RebateUploadTarget {
  final String carrier;
  final DateTime date;

  const _RebateUploadTarget({
    required this.carrier,
    required this.date,
  });
}

class _CompactMonthPicker extends StatefulWidget {
  final DateTime initialDate;

  const _CompactMonthPicker({required this.initialDate});

  @override
  State<_CompactMonthPicker> createState() => _CompactMonthPickerState();
}

class _CompactMonthPickerState extends State<_CompactMonthPicker> {
  late DateTime visibleMonth;

  @override
  void initState() {
    super.initState();
    visibleMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
  }

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final startOffset = firstDay.weekday % 7;
    final daysInMonth =
        DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final cells = List<int?>.generate(42, (index) {
      final day = index - startOffset + 1;
      return day < 1 || day > daysInMonth ? null : day;
    });

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Row(
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                visibleMonth =
                    DateTime(visibleMonth.year, visibleMonth.month - 1);
              });
            },
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Center(
              child: Text(
                DateFormat('yyyy년 M월', 'ko_KR').format(visibleMonth),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                visibleMonth =
                    DateTime(visibleMonth.year, visibleMonth.month + 1);
              });
            },
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: const ['일', '월', '화', '수', '목', '금', '토']
                  .map(
                    (day) => Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              itemCount: cells.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemBuilder: (context, index) {
                final day = cells[index];
                if (day == null) return const SizedBox.shrink();
                final date =
                    DateTime(visibleMonth.year, visibleMonth.month, day);
                final selected = DateUtils.isSameDay(date, widget.initialDate);
                final today = DateUtils.isSameDay(date, DateTime.now());
                return InkWell(
                  onTap: () => Navigator.pop(context, date),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFC94C6E)
                          : today
                              ? const Color(0xFFC94C6E).withValues(alpha: 0.10)
                              : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE8E9EF)),
                    ),
                    child: Text(
                      '$day',
                      style: TextStyle(
                        color:
                            selected ? Colors.white : const Color(0xFF111827),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, DateTime.now()),
          child: const Text('오늘'),
        ),
      ],
    );
  }
}
