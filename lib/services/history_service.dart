import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class HistoryItem {
  final String fileName;
  final String filePath;
  final String status;
  final String? signerName;
  final DateTime timestamp;
  final Map<String, dynamic> result;

  HistoryItem({
    required this.fileName,
    required this.filePath,
    required this.status,
    this.signerName,
    required this.timestamp,
    required this.result,
  });

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'filePath': filePath,
        'status': status,
        'signerName': signerName,
        'timestamp': timestamp.toIso8601String(),
        'result': result,
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        fileName: json['fileName'] as String? ?? 'Document.pdf',
        filePath: json['filePath'] as String? ?? '',
        status: json['status'] as String? ?? 'UNKNOWN',
        signerName: json['signerName'] as String?,
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
            : DateTime.now(),
        result: json['result'] as Map<String, dynamic>? ?? {},
      );
}

class HistoryService {
  static const String _fileName = 'verification_history.json';
  static List<HistoryItem>? _cachedHistory;

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<List<HistoryItem>> getHistory() async {
    if (_cachedHistory != null) return _cachedHistory!;
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        _cachedHistory = [];
        return [];
      }
      final contents = await file.readAsString();
      final List<dynamic> list = json.decode(contents);
      _cachedHistory = list
          .map((e) => HistoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return _cachedHistory!;
    } catch (e) {
      debugPrint('[HistoryService] Error reading history: $e');
      _cachedHistory = [];
      return [];
    }
  }

  static Future<void> addItem(HistoryItem item) async {
    final list = await getHistory();
    // Remove duplicate entry for the same file if exists
    list.removeWhere((existing) => existing.filePath == item.filePath);
    // Add to top of list
    list.insert(0, item);
    // Keep max 30 items
    if (list.length > 30) {
      list.removeRange(30, list.length);
    }
    _cachedHistory = list;
    await _saveHistory(list);
  }

  static Future<void> removeItem(int index) async {
    final list = await getHistory();
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      _cachedHistory = list;
      await _saveHistory(list);
    }
  }

  static Future<void> clearHistory() async {
    _cachedHistory = [];
    final file = await _getFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<void> _saveHistory(List<HistoryItem> list) async {
    try {
      final file = await _getFile();
      final data = json.encode(list.map((e) => e.toJson()).toList());
      await file.writeAsString(data);
    } catch (e) {
      debugPrint('[HistoryService] Error saving history: $e');
    }
  }
}
