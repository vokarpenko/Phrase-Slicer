import 'package:flutter/material.dart';

import 'pages/splitter_page.dart';

class PhraseSlicerApp extends StatelessWidget {
  const PhraseSlicerApp({super.key, this.enablePlayback = true});

  final bool enablePlayback;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Phrase Slicer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F6F73),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7F6),
        useMaterial3: true,
      ),
      home: SplitterPage(enablePlayback: enablePlayback),
    );
  }
}
