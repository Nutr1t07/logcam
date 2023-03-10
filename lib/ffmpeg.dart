import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_session.dart';

processPic(
    String raw, String out, bool flip, Function(FFmpegSession) callback) {
  FFmpegKit.executeAsync(
      "-i $raw"
      " -vf \"${flip ? 'hflip,' : ''}"
      "drawtext=fontfile=/system/fonts/DroidSansMono.ttf"
      ": text='%{localtime\\:%x %X}': fontcolor=white@0.5"
      ": x=h/50: y=(h-text_h)-h/50: fontsize=h/25"
      ": shadowcolor=black: shadowx=1: shadowy=1\""
      " $out",
      callback);
}

processVid(String raw, String out, double offset, bool flip,
    Function(FFmpegSession) callback) {
  FFmpegKit.executeAsync(
      "-i $raw"
      " -vcodec libx264 -crf 32"
      " -movflags use_metadata_tags"
      " -vf \"${flip ? 'hflip,' : ''}"
      "drawtext=fontfile=/system/fonts/DroidSansMono.ttf"
      ": text='%{pts\\:localtime\\:$offset\\:%x %X}': fontcolor=white@0.5"
      ": x=h/50: y=(h-text_h)-h/50: fontsize=h/25"
      ": shadowcolor=black: shadowx=1: shadowy=1\""
      " -c:a aac -b:a 8k"
      " $out",
      callback);
}
