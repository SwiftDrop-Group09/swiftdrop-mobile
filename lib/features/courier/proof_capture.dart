import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../../core/network/request_transport.dart';
import 'proof_cleanup_stub.dart' if (dart.library.io) 'proof_cleanup_io.dart';

/// Only temporary bytes enter the feature; native cache copies are removed.
abstract interface class ProofCapture {
  Future<UploadPart?> pick({required bool camera});
  Future<void> discardLost();
}

final class ImageProofCapture implements ProofCapture {
  ImageProofCapture({ImagePicker? picker}) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;
  @override
  Future<UploadPart?> pick({required bool camera}) async {
    final file = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    try {
      if (await file.length() > 5 * 1024 * 1024) {
        throw const FormatException('Proof exceeds 5 MiB.');
      }
      final bytes = await file.readAsBytes();
      return UploadPart('photo', imageMime(bytes), bytes);
    } finally {
      await deleteOwnedTemporaryProof(file.path);
    }
  }

  @override
  Future<void> discardLost() async {
    final response = await _picker.retrieveLostData();
    for (final file in response.files ?? <XFile>[]) {
      await deleteOwnedTemporaryProof(file.path);
    }
    // Lost capture has no surviving authenticated parcel binding. Never upload it.
  }
}

String imageMime(Uint8List b) {
  if (b.length >= 8 &&
      b[0] == 137 &&
      b[1] == 80 &&
      b[2] == 78 &&
      b[3] == 71 &&
      b[4] == 13 &&
      b[5] == 10 &&
      b[6] == 26 &&
      b[7] == 10) {
    return 'image/png';
  }
  if (b.length >= 3 && b[0] == 255 && b[1] == 216 && b[2] == 255) {
    return 'image/jpeg';
  }
  throw const FormatException('Use a JPEG or PNG proof image.');
}
