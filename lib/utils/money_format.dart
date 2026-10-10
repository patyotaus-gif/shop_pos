import 'package:intl/intl.dart';

final _bahtFormat = NumberFormat('#,##0.00', 'th_TH');

/// Display formatting only; never use the result for payment calculations.
String formatBaht(num amount) => '฿${_bahtFormat.format(amount)}';
