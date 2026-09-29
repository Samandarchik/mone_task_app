import 'package:dio/dio.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';

class ExcelReportService {
  final Dio _dio = sl<Dio>();

  /// Excel hisobot faylini yuklab olish
  /// [filialId] - filial ID
  /// [startDate] - boshlanish sanasi (format: yyyy-MM-dd)
  /// [endDate] - tugash sanasi (format: yyyy-MM-dd)
  /// Returns: Excel file bytes
  Future<List<int>> downloadExcelReport({
    required int filialId,
    required String startDate,
    required String endDate,
  }) async {
    try {
      final response = await _dio.get(
        AppUrls.reportsExcel,
        queryParameters: {
          'filial_id': filialId,
          'start_date': startDate,
          'end_date': endDate,
        },
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'Accept':
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          },
        ),
      );

      if (response.statusCode == 200) {
        return response.data as List<int>;
      } else {
        throw Exception(
          "${tr("Excel faylni yuklab bo'lmadi")} (${response.statusCode})",
        );
      }
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception('${tr('Server xatoligi')} (${e.response?.statusCode})');
      } else {
        throw Exception(tr('Internetga ulanib boʻlmadi'));
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Excel hisobot faylini yuklab olish va path qaytarish
  Future<String> downloadAndSaveExcel({
    required int filialId,
    required String filialName,
    required String startDate,
    required String endDate,
    required String savePath,
  }) async {
    try {
      final response = await _dio.download(
        AppUrls.reportsExcel,
        savePath,
        queryParameters: {
          'filial_id': filialId,
          'start_date': startDate,
          'end_date': endDate,
        },
        options: Options(
          headers: {
            'Accept':
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          },
        ),
      );

      if (response.statusCode == 200) {
        return savePath;
      } else {
        throw Exception(
          "${tr("Excel faylni yuklab bo'lmadi")} (${response.statusCode})",
        );
      }
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception('${tr('Server xatoligi')} (${e.response?.statusCode})');
      } else if (e.type == DioExceptionType.connectionTimeout) {
        throw Exception(tr('Ulanish vaqti tugadi. Qayta urinib koʻring.'));
      } else if (e.type == DioExceptionType.receiveTimeout) {
        throw Exception(
          tr('Maʼlumot kutish vaqti tugadi. Qayta urinib koʻring.'),
        );
      } else {
        throw Exception(tr('Internetga ulanib boʻlmadi'));
      }
    } catch (e) {
      rethrow;
    }
  }
}
