// flutter run -d emulator-5554 -t tool/preview_companion.dart
// Local visual harness: does not initialise Supabase or change the user's profile.
import 'package:flutter/material.dart';
import 'package:join_app/core/widgets/companion_view.dart';

void main() => runApp(const CompanionPreview());

class CompanionPreview extends StatefulWidget {
  const CompanionPreview({super.key});

  @override
  State<CompanionPreview> createState() => _CompanionPreviewState();
}

class _CompanionPreviewState extends State<CompanionPreview> {
  CompanionMotion _motion = CompanionMotion.greet;
  int _reaction = 0;
  String _companion = 'ELI';
  bool _dark = false;
  bool _reducedMotion = false;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff8460c6),
      brightness: _dark ? Brightness.dark : Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: Builder(
          builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: _reducedMotion),
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('Compañeros de Join'),
                    actions: [
                      IconButton(
                        tooltip: 'Cambiar tema',
                        icon: Icon(_dark ? Icons.light_mode : Icons.dark_mode),
                        onPressed: () => setState(() => _dark = !_dark),
                      )
                    ],
                  ),
                  body: SafeArea(
                    child: Column(children: [
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'DRAGO', label: Text('Drago')),
                          ButtonSegment(value: 'ELI', label: Text('Eli')),
                          ButtonSegment(value: 'HALO', label: Text('Halo')),
                        ],
                        selected: {_companion},
                        onSelectionChanged: (selection) => setState(() {
                          _companion = selection.single;
                          _motion = CompanionMotion.greet;
                          _reaction++;
                        }),
                      ),
                      const SizedBox(height: 12),
                      const Text('Un saludo, una mirada y seguimos explorando.',
                          textAlign: TextAlign.center),
                      Expanded(
                        child: Center(
                            child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: CompanionView(
                            asset: 'assets/images/mascota/$_companion.png',
                            motion: _motion,
                            reaction: _reaction,
                          ),
                        )),
                      ),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final size in [32.0, 48.0, 72.0])
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: CircleAvatar(
                                  radius: size / 2,
                                  backgroundColor: scheme.secondaryContainer,
                                  child: ClipOval(
                                      child: CompanionView(
                                    asset:
                                        'assets/images/mascota/$_companion.png',
                                    width: size,
                                    height: size,
                                    portrait: true,
                                    motion: _motion,
                                    reaction: _reaction,
                                  )),
                                ),
                              ),
                          ]),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final entry in const {
                              CompanionMotion.greet: 'Saludar',
                              CompanionMotion.thinking: 'Pensar',
                              CompanionMotion.nod: 'Asentir',
                              CompanionMotion.celebrate: 'Celebrar',
                              CompanionMotion.idle: 'Reposo',
                            }.entries)
                              FilledButton.tonal(
                                onPressed: () => setState(() {
                                  _motion = entry.key;
                                  _reaction++;
                                }),
                                child: Text(entry.value),
                              ),
                          ],
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('Movimiento reducido'),
                        value: _reducedMotion,
                        onChanged: (value) =>
                            setState(() => _reducedMotion = value),
                      ),
                    ]),
                  ),
                ),
              )),
    );
  }
}
