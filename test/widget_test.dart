import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the phrase cutter workspace', (tester) async {
    await tester.pumpWidget(const PhraseCutterApp(enablePlayback: false));

    expect(find.text('Phrase Cutter'), findsOneWidget);
    expect(find.text('Фразы'), findsOneWidget);
    expect(find.text('Экспорт'), findsOneWidget);
  });
}
