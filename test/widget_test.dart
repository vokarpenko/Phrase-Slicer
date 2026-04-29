import 'package:flutter_test/flutter_test.dart';
import 'package:phrase_slicer/src/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the phrase cutter workspace', (tester) async {
    await tester.pumpWidget(const PhraseSlicerApp(enablePlayback: false));

    expect(find.text('Phrase Slicer'), findsOneWidget);
    expect(find.text('Фразы'), findsOneWidget);
    expect(find.text('Экспорт'), findsOneWidget);
  });
}
