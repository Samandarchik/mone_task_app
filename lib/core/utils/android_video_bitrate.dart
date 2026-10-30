// ignore_for_file: implementation_imports, invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'package:camera_android_camerax/src/camerax_library.g.dart' as camerax;

/// `camera` plagini Android'da [CameraController.videoBitrate] ni e'tiborsiz
/// qoldiradi (Recorder faqat qualitySelector bilan yaratiladi) va video
/// qurilma profilidagi yuqori bitrate bilan yoziladi. Recorder yaratilishiga
/// aralashib, bitrate shu yerda beriladi. Plagin yangilansa va bu joy
/// o'zgarsa, build xato beradi — shuning uchun versiyasi pubspec'da qotirilgan.
void setAndroidVideoBitrate(int bitrate) {
  camerax.PigeonOverrides.recorder_new =
      ({aspectRatio, targetVideoEncodingBitRate, qualitySelector}) =>
          camerax.Recorder.pigeon_new(
            aspectRatio: aspectRatio,
            targetVideoEncodingBitRate: bitrate,
            qualitySelector: qualitySelector,
          );
}
