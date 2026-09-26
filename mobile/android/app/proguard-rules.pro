# google_mlkit_text_recognition ships a single Dart/Kotlin API surface that
# can address several *optional* on-device script recognizer modules
# (Chinese, Devanagari, Japanese, Korean). This app only depends on the
# base google_mlkit_text_recognition package (Latin-script recognizer) --
# it does not add google_mlkit_text_recognition_chinese/devanagari/
# japanese/korean, since none of this project's OCR targets those scripts
# (Gujarati script itself is not covered by any on-device ML Kit text
# recognizer option; Gujarati-script documents are routed through the
# Gemini-API OCR path elsewhere in this app, not ML Kit).
#
# Because those optional script classes are referenced by the plugin's
# compiled Kotlin glue code but never bundled, R8 fails release
# minification with "Missing class ... ChineseTextRecognizerOptions" etc.
# unless told these are expected/optional. This is ML Kit's own documented
# multi-script plugin design, not a real missing dependency -- see
# https://pub.dev/packages/google_mlkit_text_recognition#note.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
