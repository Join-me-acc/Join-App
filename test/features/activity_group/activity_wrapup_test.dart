import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:join_app/core/models/activity_model.dart';
import 'package:join_app/features/activity_group/presentation/widgets/activity_wrapup.dart';

Activity endedYesterday() => Activity(
      id: 'a',
      title: 'Pichanga',
      description: '',
      category: 'Deportes',
      maxParticipants: 10,
      organizerName: 'Orga',
      eventDateTime: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      durationMinutes: 60,
    );

Widget wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Column(children: [child])));

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es');
  });

  testWidgets('el aviso ofrece calificar sólo a quien le falta', (tester) async {
    var rated = false;
    await tester.pumpWidget(wrap(ActivityWrapUpBanner(
      activity: endedYesterday(),
      needsRating: true,
      onRate: () => rated = true,
      onMural: () {},
      onClan: () {},
    )));
    expect(find.text('El plan terminó'), findsOneWidget);
    expect(find.textContaining('Este chat se cierra en'), findsOneWidget);
    await tester.tap(find.text('Calificar'));
    expect(rated, isTrue);

    await tester.pumpWidget(wrap(ActivityWrapUpBanner(
      activity: endedYesterday(),
      needsRating: false,
      onRate: () {},
      onMural: () {},
      onClan: () {},
    )));
    expect(find.text('Calificar'), findsNothing);
    expect(find.text('Crear clan con el grupo'), findsOneWidget);
    expect(find.text('Mural de recuerdos'), findsOneWidget);
  });

  testWidgets('con el chat cerrado se ofrece el mural y seguir en un clan',
      (tester) async {
    var clan = false;
    await tester.pumpWidget(wrap(ClosedChatBar(
      activity: endedYesterday(),
      onMural: () {},
      onClan: () => clan = true,
    )));
    expect(find.textContaining('Este chat se cerró'), findsOneWidget);
    await tester.tap(find.text('Seguir en un clan'));
    expect(clan, isTrue);
  });
}
