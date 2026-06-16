import 'dart:io' show File, Platform;

import 'package:excel/excel.dart' as xls;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class CustomerExcelExportResult {
  final bool success;
  final bool cancelled;
  final String message;
  final String? fileName;
  final String storeLabel;
  final String dateLabel;

  const CustomerExcelExportResult({
    required this.success,
    required this.cancelled,
    required this.message,
    this.fileName,
    this.storeLabel = '',
    this.dateLabel = '',
  });
}

class CustomerExcelExportService {
  const CustomerExcelExportService();

  Future<CustomerExcelExportResult> exportCustomers({
    required List<Map<String, dynamic>> rows,
    String prefix = '고객DB',
    String selectedDateText = '',
    String fallbackDateLabel = '전체기간',
  }) async {
    if (rows.isEmpty) {
      return const CustomerExcelExportResult(
        success: false,
        cancelled: false,
        message: '내보낼 고객 데이터가 없습니다.',
      );
    }
    if (kIsWeb) {
      return const CustomerExcelExportResult(
        success: false,
        cancelled: false,
        message: '웹에서는 아직 엑셀 저장을 지원하지 않습니다.',
      );
    }
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return const CustomerExcelExportResult(
        success: false,
        cancelled: false,
        message: '엑셀 저장은 PC에서만 지원됩니다.',
      );
    }

    final storeLabel = buildStoreLabel(
      rows.map((row) => row['store']),
      fallback: '전체매장',
    );
    final dateLabel = buildDateLabel(
      selectedText: selectedDateText,
      dates: rows.map((row) => dateText(row['join_date'])),
      fallback: fallbackDateLabel,
    );
    final suggestedName =
        '${sanitizeFilePart(prefix)}_${sanitizeFilePart(storeLabel)}_${sanitizeFilePart(dateLabel)}.xlsx';

    const typeGroup = XTypeGroup(label: 'Excel', extensions: ['xlsx']);
    final saveLocation = await getSaveLocation(
      acceptedTypeGroups: const [typeGroup],
      suggestedName: suggestedName,
      confirmButtonText: '저장',
    );
    if (saveLocation == null) {
      return CustomerExcelExportResult(
        success: false,
        cancelled: true,
        message: '엑셀 저장이 취소되었습니다.',
        fileName: suggestedName,
        storeLabel: storeLabel,
        dateLabel: dateLabel,
      );
    }

    final excel = _buildWorkbook(rows);
    final bytes = excel.save(fileName: suggestedName);
    if (bytes == null || bytes.isEmpty) {
      return CustomerExcelExportResult(
        success: false,
        cancelled: false,
        message: '엑셀 파일 생성에 실패했습니다.',
        fileName: suggestedName,
        storeLabel: storeLabel,
        dateLabel: dateLabel,
      );
    }

    await File(saveLocation.path).writeAsBytes(bytes, flush: true);
    return CustomerExcelExportResult(
      success: true,
      cancelled: false,
      message: '고객DB 엑셀 저장이 완료되었습니다.',
      fileName: suggestedName,
      storeLabel: storeLabel,
      dateLabel: dateLabel,
    );
  }

  static String dateText(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('yyyy-MM-dd').format(parsed);
  }

  static String buildStoreLabel(
    Iterable<dynamic> stores, {
    required String fallback,
  }) {
    final uniqueStores = stores
        .map((store) => store?.toString().trim() ?? '')
        .where((store) => store.isNotEmpty && store != '-')
        .toSet()
        .toList()
      ..sort();

    if (uniqueStores.isEmpty) return fallback;
    if (uniqueStores.length == 1) return uniqueStores.first;
    return '${uniqueStores.first} 외${uniqueStores.length - 1}개';
  }

  static String buildDateLabel({
    required String selectedText,
    required Iterable<String> dates,
    required String fallback,
  }) {
    final normalizedSelected = selectedText.trim().replaceAll(' ~ ', '~');
    if (normalizedSelected.isNotEmpty) return normalizedSelected;

    final uniqueDates = dates
        .map((date) => date.trim())
        .where((date) => date.isNotEmpty && date != '-')
        .toSet()
        .toList()
      ..sort();

    if (uniqueDates.isEmpty) return fallback;
    if (uniqueDates.length == 1) return uniqueDates.first;
    return '${uniqueDates.first} 외${uniqueDates.length - 1}일';
  }

  static String sanitizeFilePart(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? '미지정' : cleaned;
  }

  xls.Excel _buildWorkbook(List<Map<String, dynamic>> rows) {
    final excel = xls.Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    const sheetName = '고객DB';
    if (defaultSheet != null && defaultSheet != sheetName) {
      excel.rename(defaultSheet, sheetName);
    }
    final sheet = excel[sheetName];

    final columns = _columnsFor(rows);
    excel.appendRow(
      sheetName,
      columns.map((column) => xls.TextCellValue(column.header)).toList(),
    );

    for (final row in rows) {
      excel.appendRow(
        sheetName,
        columns.map((column) => column.cellValue(row)).toList(),
      );
    }

    _styleSheet(sheet, rows.length, columns);
    return excel;
  }

  List<_CustomerExcelColumn> _columnsFor(List<Map<String, dynamic>> rows) {
    final known = _baseColumns.map((column) => column.key).toSet();
    final extraKeys = rows
        .expand((row) => row.keys)
        .where((key) => !known.contains(key))
        .toSet()
        .toList()
      ..sort();

    return [
      ..._baseColumns,
      for (final key in extraKeys)
        _CustomerExcelColumn(
          key: key,
          header: key,
          width: 18,
          value: (row) => row[key],
        ),
    ];
  }

  void _styleSheet(
    xls.Sheet sheet,
    int rowCount,
    List<_CustomerExcelColumn> columns,
  ) {
    final headerStyle = xls.CellStyle(
      bold: true,
      fontColorHex: xls.ExcelColor.white,
      backgroundColorHex: xls.ExcelColor.blueGrey600,
      horizontalAlign: xls.HorizontalAlign.Center,
      verticalAlign: xls.VerticalAlign.Center,
      leftBorder: xls.Border(borderStyle: xls.BorderStyle.Thin),
      rightBorder: xls.Border(borderStyle: xls.BorderStyle.Thin),
      topBorder: xls.Border(borderStyle: xls.BorderStyle.Thin),
      bottomBorder: xls.Border(borderStyle: xls.BorderStyle.Thin),
    );
    final moneyStyle = xls.CellStyle(
      numberFormat: xls.NumFormat.standard_3,
      horizontalAlign: xls.HorizontalAlign.Right,
      verticalAlign: xls.VerticalAlign.Center,
    );

    for (var i = 0; i < columns.length; i++) {
      sheet.setColumnWidth(i, columns[i].width);
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .cellStyle = headerStyle;
    }

    for (var rowIndex = 1; rowIndex <= rowCount; rowIndex++) {
      for (var columnIndex = 0; columnIndex < columns.length; columnIndex++) {
        if (!columns[columnIndex].money) continue;
        sheet
            .cell(
              xls.CellIndex.indexByColumnRow(
                columnIndex: columnIndex,
                rowIndex: rowIndex,
              ),
            )
            .cellStyle = moneyStyle;
      }
    }
  }
}

class _CustomerExcelColumn {
  final String key;
  final String header;
  final double width;
  final bool money;
  final dynamic Function(Map<String, dynamic> row) value;

  const _CustomerExcelColumn({
    required this.key,
    required this.header,
    required this.width,
    required this.value,
    this.money = false,
  });

  xls.CellValue cellValue(Map<String, dynamic> row) {
    final resolved = value(row);
    if (resolved == null) return xls.TextCellValue('');
    if (resolved is bool) return xls.BoolCellValue(resolved);
    if (resolved is int) return xls.IntCellValue(resolved);
    if (resolved is double) return xls.DoubleCellValue(resolved);
    return xls.TextCellValue(resolved.toString());
  }
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
}

final List<_CustomerExcelColumn> _baseColumns = [
  _CustomerExcelColumn(
    key: 'id',
    header: 'ID',
    width: 36,
    value: (row) => row['id'],
  ),
  _CustomerExcelColumn(
    key: 'join_date',
    header: '가입일',
    width: 13,
    value: (row) => CustomerExcelExportService.dateText(row['join_date']),
  ),
  _CustomerExcelColumn(
    key: 'created_at',
    header: '등록일',
    width: 18,
    value: (row) => CustomerExcelExportService.dateText(row['created_at']),
  ),
  _CustomerExcelColumn(
    key: 'm3',
    header: 'M+3',
    width: 12,
    value: (row) => row['m3'],
  ),
  _CustomerExcelColumn(
    key: 'm6',
    header: 'M+6',
    width: 12,
    value: (row) => row['m6'],
  ),
  _CustomerExcelColumn(
    key: 'store',
    header: '매장',
    width: 14,
    value: (row) => row['store'],
  ),
  _CustomerExcelColumn(
    key: 'staff',
    header: '담당자',
    width: 12,
    value: (row) => row['staff'],
  ),
  _CustomerExcelColumn(
    key: 'name',
    header: '고객명',
    width: 12,
    value: (row) => row['name'],
  ),
  _CustomerExcelColumn(
    key: 'phone',
    header: '휴대폰번호',
    width: 16,
    value: (row) => row['phone'],
  ),
  _CustomerExcelColumn(
    key: 'join_type',
    header: '가입유형',
    width: 12,
    value: (row) => row['join_type'],
  ),
  _CustomerExcelColumn(
    key: 'carrier',
    header: '통신사',
    width: 12,
    value: (row) => row['carrier'],
  ),
  _CustomerExcelColumn(
    key: 'previous_carrier',
    header: '기존통신사',
    width: 12,
    value: (row) => row['previous_carrier'],
  ),
  _CustomerExcelColumn(
    key: 'model',
    header: '모델명',
    width: 16,
    value: (row) => row['model'],
  ),
  _CustomerExcelColumn(
    key: 'plan',
    header: '요금제',
    width: 16,
    value: (row) => row['plan'],
  ),
  _CustomerExcelColumn(
    key: 'add_service',
    header: '부가서비스',
    width: 18,
    value: (row) => row['add_service'],
  ),
  _CustomerExcelColumn(
    key: 'contract_type',
    header: '공시/선약',
    width: 12,
    value: (row) => row['contract_type'],
  ),
  _CustomerExcelColumn(
    key: 'installment',
    header: '할부개월',
    width: 10,
    value: (row) => row['installment'],
  ),
  _CustomerExcelColumn(
    key: 'rebate',
    header: '리베이트',
    width: 13,
    money: true,
    value: (row) => _toInt(row['rebate']),
  ),
  _CustomerExcelColumn(
    key: 'add_rebate',
    header: '부가리베이트',
    width: 13,
    money: true,
    value: (row) => _toInt(row['add_rebate']),
  ),
  _CustomerExcelColumn(
    key: 'hidden_rebate',
    header: '히든리베이트',
    width: 13,
    money: true,
    value: (row) => _toInt(row['hidden_rebate']),
  ),
  _CustomerExcelColumn(
    key: 'hidden_note',
    header: '히든내용',
    width: 20,
    value: (row) => row['hidden_note'],
  ),
  _CustomerExcelColumn(
    key: 'deduction',
    header: '차감',
    width: 13,
    money: true,
    value: (row) => _toInt(row['deduction']),
  ),
  _CustomerExcelColumn(
    key: 'deduction_note',
    header: '차감내용',
    width: 20,
    value: (row) => row['deduction_note'],
  ),
  _CustomerExcelColumn(
    key: 'support_money',
    header: '유통망지원금',
    width: 14,
    money: true,
    value: (row) => _toInt(row['support_money']),
  ),
  _CustomerExcelColumn(
    key: 'payment',
    header: '결제',
    width: 13,
    money: true,
    value: (row) => _toInt(row['payment']),
  ),
  _CustomerExcelColumn(
    key: 'payment_note',
    header: '결제내용',
    width: 20,
    value: (row) => row['payment_note'],
  ),
  _CustomerExcelColumn(
    key: 'deposit',
    header: '입금',
    width: 13,
    money: true,
    value: (row) => _toInt(row['deposit']),
  ),
  _CustomerExcelColumn(
    key: 'bank_info',
    header: '은행정보',
    width: 24,
    value: (row) => row['bank_info'],
  ),
  _CustomerExcelColumn(
    key: 'trade_in',
    header: '반납',
    width: 9,
    value: (row) => row['trade_in'],
  ),
  _CustomerExcelColumn(
    key: 'trade_model',
    header: '반납모델',
    width: 16,
    value: (row) => row['trade_model'],
  ),
  _CustomerExcelColumn(
    key: 'trade_price',
    header: '매입금액',
    width: 13,
    money: true,
    value: (row) => _toInt(row['trade_price']),
  ),
  _CustomerExcelColumn(
    key: 'total_rebate',
    header: '총리베이트',
    width: 13,
    money: true,
    value: (row) => _toInt(row['total_rebate']),
  ),
  _CustomerExcelColumn(
    key: 'tax',
    header: '세금',
    width: 12,
    money: true,
    value: (row) => _toInt(row['tax']),
  ),
  _CustomerExcelColumn(
    key: 'margin',
    header: '마진',
    width: 13,
    money: true,
    value: (row) => _toInt(row['margin']),
  ),
  _CustomerExcelColumn(
    key: 'memo',
    header: '메모',
    width: 28,
    value: (row) => row['memo'],
  ),
  _CustomerExcelColumn(
    key: 'plan_change_add_service_delete',
    header: '요변/부가삭제',
    width: 24,
    value: (row) => row['plan_change_add_service_delete'],
  ),
  _CustomerExcelColumn(
    key: 'mobile',
    header: '모바일',
    width: 12,
    value: (row) => row['mobile'],
  ),
  _CustomerExcelColumn(
    key: 'second',
    header: '2nd',
    width: 12,
    value: (row) => row['second'],
  ),
  _CustomerExcelColumn(
    key: 'created_by',
    header: '등록자ID',
    width: 36,
    value: (row) => row['created_by'],
  ),
  _CustomerExcelColumn(
    key: 'is_deleted',
    header: '삭제여부',
    width: 10,
    value: (row) => row['is_deleted'],
  ),
  _CustomerExcelColumn(
    key: 'deleted_at',
    header: '삭제일',
    width: 18,
    value: (row) => CustomerExcelExportService.dateText(row['deleted_at']),
  ),
  _CustomerExcelColumn(
    key: 'deleted_by',
    header: '삭제자ID',
    width: 36,
    value: (row) => row['deleted_by'],
  ),
];
