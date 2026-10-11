import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';

import 'receipt.dart';

/// Printer settings kept on the device.
class PrintSettings {
  PrintSettings({required this.paper, required this.autoPos});
  int paper; // 58 or 80 (mm)
  bool autoPos; // shop sales: the "Print receipt" box starts ticked (website orders always print on Accept)

  int get dots => paper == 80 ? 576 : 384;

  static Future<PrintSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return PrintSettings(
      paper: p.getInt('print_paper') ?? 58,
      autoPos: p.getBool('print_pos_default') ?? false,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('print_paper', paper);
    await p.setBool('print_pos_default', autoPos);
  }
}

/// Prints receipts on the Sunmi built-in printer.
class ReceiptPrinter {
  static bool _bound = false;

  /// Returns null when it printed, otherwise a message for the staff.
  static Future<String?> print(ReceiptData d) async {
    try {
      final cfg = await PrintSettings.load();
      final png = await renderReceipt(d, cfg.dots);
      if (!_bound) {
        // ignore: deprecated_member_use
        final ok = await SunmiPrinter.bindingPrinter();
        if (ok == false) return 'Printer not found on this device';
        _bound = true;
      }
      // ignore: deprecated_member_use
      await SunmiPrinter.initPrinter();
      await SunmiPrinter.printImage(png, align: SunmiPrintAlign.CENTER);
      await SunmiPrinter.lineWrap(3);
      await SunmiPrinter.cutPaper();
      return null;
    } catch (e) {
      _bound = false;
      return 'Could not print: $e';
    }
  }

  /// A sample receipt to check the printer and the paper size.
  static Future<String?> test() => print(ReceiptData(
        ref: 'TEST',
        time: DateTime.now(),
        source: 'pos',
        items: [ReceiptItem(qty: 1, nameEn: 'Test print', nameAr: 'تجربة طباعة', price: 0)],
        total: 0,
        payment: 'cash',
        stamps: '3/6',
      ));
}
