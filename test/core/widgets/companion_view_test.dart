
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:join_app/core/widgets/companion_view.dart';

void main() {
  const eli = 'assets/images/mascota/ELI.png';
  final boundaryKey = GlobalKey();

  Widget scene(
          {bool reduced = false,
          bool ticker = true,
          String asset = eli,
          CompanionMotion motion = CompanionMotion.greet,
          int reaction = 0}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: TickerMode(
            enabled: ticker,
            child: Center(
                child: RepaintBoundary(
              key: boundaryKey,
              child: ColoredBox(
                color: const Color(0xfff5f1fa),
                child: CompanionView(
                    asset: asset,
                    width: 360,
                    height: 540,
                    motion: motion,
                    reaction: reaction),
              ),
            )),
          ),
        ),
      );

  Future<void> load(WidgetTester tester, [String asset = eli]) async {
    final context = tester.element(find.byType(CompanionView));
    await tester.runAsync(() async {
      await precacheImage(ResizeImage(AssetImage(asset), width: 640), context);
      await precacheImage(
          ResizeImage(AssetImage(asset.replaceFirst('.png', '-blink.png')),
              width: 640),
          context);
    });
    await tester.pump();
  }

  Future<Uint8List> pixels(WidgetTester tester, [String? capture]) async {
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    return (await tester.runAsync(() async {
      final image = await boundary.toImage();
      final raw = (await image.toByteData())!.buffer.asUint8List();
      if (const bool.fromEnvironment('COMPANION_CAPTURE') && capture != null) {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/companion-review/$capture.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(png!.buffer.asUint8List());
      }
      image.dispose();
      return raw;
    }))!;
  }

  for (final character in const [
    ('ELI', Rect.fromLTWH(165, 100, 25, 25), Rect.fromLTWH(90, 480, 120, 20)),
    ('HALO', Rect.fromLTWH(148, 110, 25, 25), Rect.fromLTWH(133, 487, 100, 14)),
  ]) {
    final (name, eye, feet) = character;
    final asset = 'assets/images/mascota/$name.png';
    testWidgets(
        '$name renders independent gestures and eyelids without exceptions',
        (tester) async {
      await tester.pumpWidget(scene(asset: asset));
      await load(tester, asset);
      final resting = await pixels(tester, '${name.toLowerCase()}-rest');
      await tester.pump(const Duration(milliseconds: 430));
      final waving = await pixels(tester, '${name.toLowerCase()}-wave');
      expect(waving, isNot(orderedEquals(resting)));
      await tester.pump(const Duration(milliseconds: 2170));
      final closed = await pixels(tester, '${name.toLowerCase()}-blink');
      expect(closed, isNot(orderedEquals(waving)));
      // The pupil really gets covered by the eyelids; a breathing-only
      // implementation or a missing blink asset must not pass this check.
      double eyeLight(Uint8List frame) {
        var sum = 0;
        for (var y = eye.top.toInt(); y < eye.bottom; y++) {
          for (var x = eye.left.toInt(); x < eye.right; x++) {
            final index = (y * 360 + x) * 4;
            sum += frame[index] + frame[index + 1] + frame[index + 2];
          }
        }
        return sum / (eye.width * eye.height);
      }

      expect(eyeLight(closed) - eyeLight(resting), greaterThan(80));
      // A hand/head gesture leaves the feet planted instead of floating the PNG.
      for (var y = feet.top.toInt(); y < feet.bottom; y++) {
        final start = (y * 360 + feet.left.toInt()) * 4;
        final end = (y * 360 + feet.right.toInt()) * 4;
        expect(waving.sublist(start, end),
            orderedEquals(resting.sublist(start, end)));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets('reduced motion freezes the artwork and schedules no animation',
      (tester) async {
    await tester.pumpWidget(scene(reduced: true));
    await load(tester);
    final before = await pixels(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(await pixels(tester), orderedEquals(before));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(scene(reduced: false));
    await tester.pump(const Duration(milliseconds: 430));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hidden route pauses and a changed companion releases the rig',
      (tester) async {
    await tester.pumpWidget(scene());
    await load(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(scene(ticker: false));
    expect(tester.binding.transientCallbackCount, 0);
    // An unrigged existing asset is still supported as a static fallback.
    await tester.pumpWidget(scene(asset: 'assets/images/join.png'));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(scene(motion: CompanionMotion.nod, reaction: 1));
    await load(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'switching between all companions replaces images without stale frames',
      (tester) async {
    for (final name in ['ELI', 'DRAGO', 'HALO', 'ELI']) {
      final asset = 'assets/images/mascota/$name.png';
      await tester.pumpWidget(scene(asset: asset));
      await load(tester, asset);
      await tester.pump(const Duration(milliseconds: 2600));
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(scene(asset: asset, reduced: true));
      final frozen = await pixels(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(await pixels(tester), orderedEquals(frozen));
      expect(tester.binding.transientCallbackCount, 0);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
