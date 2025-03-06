library dart_libass;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:ffi';
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;
import 'package:ffi/ffi.dart';
import 'dart:io';

import 'package:libass_binding/bindings.dart';

class DartLibass {
  List<File> fonts;
  File defaultFont;
  String defaultFamily;
  File subtitle;
  int width;
  int height;
  late Directory temp;
  late ffi.DynamicLibrary dylib;
  late LibassBindings bindings;
  late ffi.Pointer<ASS_Library> library;
  late ffi.Pointer<ASS_Renderer> renderer;
  late ffi.Pointer<ffi.Int> changePtr = ffi.nullptr;
  late ffi.Pointer<ASS_Track> track = ffi.nullptr;

  DartLibass({
    required this.fonts,
    required this.defaultFont,
    required this.defaultFamily,
    required this.subtitle,
    required this.width,
    required this.height,
  });

  init() async {
    changePtr = calloc.allocate(ffi.sizeOf<ffi.Int>()).cast<ffi.Int>();

    String libPath = '';
    if (Platform.isMacOS) {
      libPath = 'assets/macos/libass.9.dylib';
    }

    if (Platform.isWindows) {
      libPath = 'assets/windows/libass.dll';
    }

    if (Platform.isOhos){
      libPath = '/data/storage/el1/bundle/libs/arm64/libentry.so';
    }
    dylib = ffi.DynamicLibrary.open(libPath);
    bindings = LibassBindings(dylib);
    print("ASS: Open done");

    library = bindings.ass_library_init();
    print("ASS: ass_library_init");
    renderer = bindings.ass_renderer_init(library);
    print("ASS: ass_renderer_init");


    // create temp folder with fonts
    temp = await Directory("/data/storage/el2/base/haps/entry/cache/").createTemp("fonts");
    print("ASS: Fonts Copy start: ");
    for (var font in fonts) {
      print("ASS: ${await font.length()} ${temp.path}/${font.uri.pathSegments.last}");
      font.copySync("${temp.path}/${font.uri.pathSegments.last}");
    }
    print("ASS: Fonts Copy done");
    ffi.Pointer<ffi.Char> fontDirFfiPath =
        temp.path.toNativeUtf8().cast<ffi.Char>();
    print("ASS: Fonts Open done");
    bindings.ass_set_fonts_dir(library, fontDirFfiPath);

    bindings.ass_set_fonts(
      renderer,
      defaultFont.uri.path.toNativeUtf8().cast<ffi.Char>(),
      defaultFamily.toNativeUtf8().cast<ffi.Char>(),
      1,
      ffi.nullptr,
      0,
    );

    print("ASS: Fonts set done");

    ffi.Pointer<ffi.Char> filePath =
        subtitle.uri.path.toNativeUtf8().cast<ffi.Char>();

    track = bindings.ass_read_file(library, filePath, ffi.nullptr);
    print("ASS: read file");
  }

  setTrack(File subtitle) {
    ffi.Pointer<ffi.Char> filePath =
        subtitle.uri.path.toNativeUtf8().cast<ffi.Char>();

    track = bindings.ass_read_file(library, filePath, ffi.nullptr);
  }

  dispose() {
    bindings.ass_clear_fonts(library);
    bindings.ass_renderer_done(renderer);
    bindings.ass_library_done(library);
  }

  getFrame(int timestamp) async {
    bindings.ass_set_frame_size(renderer, width, height);

    ffi.Pointer<ASS_Image> frameImage =
        bindings.ass_render_frame(renderer, track, timestamp, changePtr);

    if (changePtr.value == 0) return;

    if (frameImage == ffi.nullptr) return;

    Uint8List memory = Uint8List(4 * width * height);
    memory.fillRange(0, memory.length, 0);

    while (frameImage != ffi.nullptr) {
      ass_image imageRef = frameImage.ref;
      int color = imageRef.color;
      var r = (color >> 24) & 0xFF;
      var g = (color >> 16) & 0xFF;
      var b = (color >> 8) & 0xFF;
      var a = 255 - color & 0xFF;

      for (int y = 0; y < imageRef.h; ++y) {
        for (int x = 0; x < imageRef.w; ++x) {
          int offset = y * imageRef.stride + x;
          int opacity = imageRef.bitmap.elementAt(offset).value;
          if (opacity == 0) {
            continue;
          }

          int listOffset =
              4 * ((imageRef.dst_y + y) * width + (imageRef.dst_x + x));

          double srcOpacity = a / 255 * opacity / 255;
          double oneMinusSrc = 1.0 - srcOpacity;

          memory[listOffset + 0] =
              (memory[listOffset + 0] * oneMinusSrc + srcOpacity * r)
                  .toInt()
                  .clamp(0, 255);
          memory[listOffset + 1] =
              (memory[listOffset + 1] * oneMinusSrc + srcOpacity * g)
                  .toInt()
                  .clamp(0, 255);
          memory[listOffset + 2] =
              (memory[listOffset + 2] * oneMinusSrc + srcOpacity * b)
                  .toInt()
                  .clamp(0, 255);
          int targetAlpha = memory[listOffset + 3] + (srcOpacity * 255).toInt();
          memory[listOffset + 3] = targetAlpha.clamp(0, 255);
        }
      }

      frameImage = imageRef.next;
    }

    Future decodeImageFromPixels() async {
      Completer c = Completer();

      ui.decodeImageFromPixels(
        memory,
        width,
        height,
        ui.PixelFormat.rgba8888,
        (value) {
          c.complete(value);
        },
      );

      return c.future;
    }

    ui.Image img = await decodeImageFromPixels();

    return img;
  }
}
