import 'package:supabase_flutter/supabase_flutter.dart';

/// PostgREST는 서버 기본값(1000행)에서 조용히 잘라 반환하므로, 전량 로드가
/// 필요한 화면(고객DB/가망고객/고객정리 등)은 이 헬퍼로 range 페이지를 끝까지
/// 순회한다. 잘리면 최신 데이터부터 화면·엑셀에서 누락되는 버그가 된다.
///
/// [buildQuery]는 호출될 때마다 동일한 조건의 새 쿼리 빌더를 반환해야 한다
/// (빌더는 1회용이라 재사용할 수 없음).
Future<List<Map<String, dynamic>>> fetchAllRows(
  PostgrestTransformBuilder<PostgrestList> Function() buildQuery, {
  int pageSize = 1000,
}) async {
  final all = <Map<String, dynamic>>[];
  var from = 0;
  while (true) {
    final page = await buildQuery().range(from, from + pageSize - 1);
    all.addAll(List<Map<String, dynamic>>.from(page));
    if (page.length < pageSize) break;
    from += pageSize;
  }
  return all;
}
