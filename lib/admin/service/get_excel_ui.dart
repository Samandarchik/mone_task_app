import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/get_excel_service.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class ExcelReportPage extends StatefulWidget {
  final List<FilialModel>? filials;
  final List<int>? filialIds; // Ishchi ko'ra oladigan filial ID'lari

  const ExcelReportPage({Key? key, this.filials, this.filialIds})
    : super(key: key);

  @override
  State<ExcelReportPage> createState() => _ExcelReportPageState();
}

class _ExcelReportPageState extends State<ExcelReportPage> {
  final ExcelReportService _reportService = ExcelReportService();
  final AdminTaskService _adminService = AdminTaskService();

  List<FilialModel>? _allFilials;
  List<FilialModel>? _availableFilials; // Faqat ko'ra oladigan filiallar
  FilialModel? selectedFilial;
  DateTimeRange? selectedDateRange;
  bool isLoading = false;
  bool isLoadingFilials = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeFilials();
  }

  Future<void> _initializeFilials() async {
    if (widget.filials != null && widget.filials!.isNotEmpty) {
      setState(() {
        _allFilials = widget.filials;
        _filterAvailableFilials();
      });
    } else {
      await _fetchFilials();
    }
  }

  void _filterAvailableFilials() {
    if (_allFilials == null) return;

    // Agar filialIds null yoki bo'sh bo'lsa, barcha filiallarni ko'rsatish
    if (widget.filialIds == null || widget.filialIds!.isEmpty) {
      _availableFilials = _allFilials;
    } else {
      // Faqat ruxsat berilgan filiallarni filter qilish
      _availableFilials = _allFilials!
          .where((filial) => widget.filialIds!.contains(filial.filialId))
          .toList();
    }
  }

  Future<void> _fetchFilials() async {
    setState(() {
      isLoadingFilials = true;
      errorMessage = null;
    });

    try {
      final filials = await _adminService.fetchFilials();
      setState(() {
        _allFilials = filials;
        _filterAvailableFilials();
        isLoadingFilials = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Filiallarni yuklashda xatolik: $e';
        isLoadingFilials = false;
      });
      _showSnackBar('Filiallarni yuklashda xatolik', isError: true);
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange:
          selectedDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
    );

    if (picked != null) {
      setState(() {
        selectedDateRange = picked;
      });
    }
  }

  Future<void> _downloadAndShareExcel() async {
    if (selectedFilial == null) {
      _showSnackBar('Filialni tanlang', isError: true);
      return;
    }

    if (selectedDateRange == null) {
      _showSnackBar('Sana oralig\'ini tanlang', isError: true);
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final startDate = _formatDate(selectedDateRange!.start);
      final endDate = _formatDate(selectedDateRange!.end);

      final directory = await getTemporaryDirectory();
      final fileName =
          'hisobot_${selectedFilial!.name}_${startDate}_$endDate.xlsx';
      final filePath = '${directory.path}/$fileName';

      await _reportService.downloadAndSaveExcel(
        filialId: selectedFilial!.filialId,
        filialName: selectedFilial!.name,
        startDate: startDate,
        endDate: endDate,
        savePath: filePath,
      );

      final result = await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'Hisobot - ${selectedFilial!.name}',
        text: 'Sana: $startDate dan $endDate gacha',
      );

      if (result.status == ShareResultStatus.success) {
        _showSnackBar('Muvaffaqiyatli yuborildi');
      }
    } catch (e) {
      _showSnackBar('Xatolik: $e', isError: true);
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Excel Hisobot'), centerTitle: true),
      body: isLoadingFilials
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _fetchFilials,
                    child: const Text('Qayta urinish'),
                  ),
                ],
              ),
            )
          : _availableFilials == null || _availableFilials!.isEmpty
          ? const Center(
              child: Text(
                'Sizda ko\'rish uchun ruxsat berilgan filiallar yo\'q',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Filial tanlash
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<FilialModel>(
                        isExpanded: true,
                        hint: const Text('Filialni tanlang'),
                        value: selectedFilial,
                        items: _availableFilials?.map((filial) {
                          return DropdownMenuItem<FilialModel>(
                            value: filial,
                            child: Text(filial.name),
                          );
                        }).toList(),
                        onChanged: (FilialModel? value) {
                          setState(() {
                            selectedFilial = value;
                          });
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Sana tanlash
                  InkWell(
                    onTap: () => _selectDateRange(context),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sana oralig\'i',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                selectedDateRange == null
                                    ? 'Tanlang'
                                    : '${_formatDate(selectedDateRange!.start)} - ${_formatDate(selectedDateRange!.end)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Icon(
                            Icons.calendar_today,
                            color: Colors.grey.shade600,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Yuklash tugmasi
                  ElevatedButton.icon(
                    onPressed: isLoading ? null : _downloadAndShareExcel,
                    icon: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.share),
                    label: Text(
                      isLoading ? 'Yuklanmoqda...' : 'Yuklab Yuborish',
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
