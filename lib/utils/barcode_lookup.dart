import 'dart:convert';
import 'package:http/http.dart' as http;

class BarcodeLookup {
  static Future<Map<String, String>?> lookup(String barcode) async {
    try {
      final uri = Uri.parse(
        'https://world.openfoodfacts.org/api/v0/product/$barcode.json',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['status'] != 1) return null;

      final product = data['product'] as Map<String, dynamic>?;
      if (product == null) return null;

      final name = (product['product_name_th'] as String?)?.trim() ??
          (product['product_name'] as String?)?.trim() ??
          '';

      if (name.isEmpty) return null;
      return {'name': name};
    } catch (_) {
      return null;
    }
  }
}
