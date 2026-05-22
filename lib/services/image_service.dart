import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class ImageService {
  // บีบอัด บันทึกเครื่อง และอัปโหลด Storage คืน {localPath, imageUrl}
  static Future<({String localPath, String imageUrl})> saveProduct(
      File file, String shopId, String productId) async {
    final dir = await getApplicationDocumentsDirectory();
    final destDir = Directory('${dir.path}/product_images');
    if (!await destDir.exists()) await destDir.create(recursive: true);

    final destPath = '${destDir.path}/$productId.jpg';
    final compressed = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      destPath,
      quality: 75,
      minWidth: 600,
      minHeight: 600,
    );
    final localPath = compressed?.path ?? file.path;

    // อัปโหลดขึ้น Firebase Storage
    final ref = FirebaseStorage.instance
        .ref('shops/$shopId/products/$productId.jpg');
    await ref.putFile(File(localPath));
    final imageUrl = await ref.getDownloadURL();

    return (localPath: localPath, imageUrl: imageUrl);
  }

  // ตัดพื้นหลังออก — sample สี 4 มุม แล้ว flood-fill ทำให้โปร่งแสง
  static Future<File> removeBackground(File file, {int tolerance = 40}) async {
    final bytes = await file.readAsBytes();
    final src = img.decodeImage(bytes);
    if (src == null) return file;

    final w = src.width, h = src.height;
    final out = img.Image(width: w, height: h);

    // sample background color จาก 4 มุม
    final corners = [
      src.getPixel(0, 0),
      src.getPixel(w - 1, 0),
      src.getPixel(0, h - 1),
      src.getPixel(w - 1, h - 1),
    ];
    final bgR = corners.map((p) => p.r.toInt()).reduce((a, b) => a + b) ~/ 4;
    final bgG = corners.map((p) => p.g.toInt()).reduce((a, b) => a + b) ~/ 4;
    final bgB = corners.map((p) => p.b.toInt()).reduce((a, b) => a + b) ~/ 4;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final dr = (p.r.toInt() - bgR).abs();
        final dg = (p.g.toInt() - bgG).abs();
        final db = (p.b.toInt() - bgB).abs();
        final dist = (dr + dg + db) ~/ 3;
        if (dist < tolerance) {
          out.setPixel(x, y, img.ColorRgba8(0, 0, 0, 0));
        } else {
          out.setPixel(x, y, img.ColorRgba8(
            p.r.toInt(), p.g.toInt(), p.b.toInt(), 255));
        }
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    final destPath = '${dir.path}/tmp_nobg_${DateTime.now().millisecondsSinceEpoch}.png';
    final encoded = Uint8List.fromList(img.encodePng(out));
    return File(destPath)..writeAsBytesSync(encoded);
  }

  static Future<void> deleteImage(String? path) async {
    if (path == null) return;
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
