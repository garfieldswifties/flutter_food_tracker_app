import 'dart:typed_data';
import 'dart:ui' as ui;

class FoodPhoto {
  const FoodPhoto._(this.bytes, this.mimeType, this.extension);

  static const maxBytes = 5 * 1024 * 1024;
  final Uint8List bytes;
  final String mimeType;
  final String extension;

  static Future<FoodPhoto> decode(Uint8List bytes) async {
    if (bytes.length > maxBytes) {
      throw const FormatException('ขนาดรูปต้องไม่เกิน 5 MiB');
    }

    bool matches(List<int> signature, [int offset = 0]) {
      if (bytes.length < offset + signature.length) return false;
      for (var i = 0; i < signature.length; i++) {
        if (bytes[offset + i] != signature[i]) return false;
      }
      return true;
    }

    final FoodPhoto photo;
    if (matches(const [0xff, 0xd8, 0xff])) {
      photo = FoodPhoto._(bytes, 'image/jpeg', 'jpg');
    } else if (matches(const [0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10])) {
      photo = FoodPhoto._(bytes, 'image/png', 'png');
    } else if (matches(const [82, 73, 70, 70]) &&
        matches(const [87, 69, 66, 80], 8)) {
      photo = FoodPhoto._(bytes, 'image/webp', 'webp');
    } else {
      throw const FormatException('เลือกรูป JPEG, PNG หรือ WebP');
    }

    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 128);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    } on Exception {
      throw const FormatException('เปิดรูปนี้ไม่ได้ กรุณาเลือกรูปใหม่');
    }
    return photo;
  }
}
