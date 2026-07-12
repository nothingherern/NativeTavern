import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Необходим для MethodChannel
import 'package:file_picker/file_picker.dart';
import 'package:llamadart/llamadart.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]).then((_) {
    runApp(const TranslationApp());
  });
}

class TranslationApp extends StatelessWidget {
  const TranslationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GGUF Local Translator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SelectionArea(child: TranslatorScreen()),
    );
  }
}

class TranslatorScreen extends StatefulWidget {
  const TranslatorScreen({super.key});

  @override
  State<TranslatorScreen> createState() => _TranslatorScreenState();
}

class _TranslatorScreenState extends State<TranslatorScreen> {
  // Настройка канала связи с Android-частью приложения
  static const _platform = MethodChannel(
    'com.example.aitranslator/process_text',
  );

  LlamaEngine? _engine;
  String? _modelPath;
  bool _isModelLoading = false;
  bool _isTranslating = false;

  final TextEditingController _inputController = TextEditingController();
  String _translatedText = "";

  String _sourceLang = "Русский";
  String _targetLang = "English";

  final List<String> _languages = [
    "English",
    "Русский",
    "Deutsch",
    "Español",
    "Français",
    "中文 (Chinese)",
    "日本語 (Japanese)",
    "한국어 (Korean)",
    "Italiano",
    "Português",
    "العربية (Arabic)",
    "Türkçe",
    "Nederlands",
    "Polski",
    "Українська",
    "Čeština",
    "Svenska",
    "Norsk",
    "Dansk",
    "Suomi",
    "Melayu",
    "Tiếng Việt",
    "ไทย (Thai)",
    "हिन्दी (Hindi)",
    "עברית (Hebrew)",
  ];

  @override
  void initState() {
    super.initState();
    _checkForSharedText(); // Проверка текста при холодном старте приложения

    // Настраиваем слушатель, если приложение было просто свернуто
    _platform.setMethodCallHandler((call) async {
      if (call.method == "onTextReceived") {
        final String? text = call.arguments as String?;
        if (text != null) _handleIncomingText(text);
      }
    });
  }

  // Метод получения текста из Android-активити
  Future<void> _checkForSharedText() async {
    try {
      final String? text = await _platform.invokeMethod('getSharedText');
      if (text != null && text.isNotEmpty) {
        _handleIncomingText(text);
      }
    } catch (e) {
      debugPrint("Error retrieving text: $e");
    }
  }

  void _handleIncomingText(String text) {
    setState(() {
      _inputController.text = text;
      _translatedText = "";
    });
    // Автоматически начинаем перевод, если модель загружена
    if (_engine != null) {
      _translate();
    } else {
      setState(() {
        _translatedText = "Model not loaded. Please select a GGUF model.";
      });
    }
  }

  @override
  void dispose() {
    _engine?.dispose();
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _pickAndLoadModel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;

        if (!path.toLowerCase().endsWith('.gguf')) {
          setState(() {
            _translatedText =
                "Error: Invalid file selected. Please select a file with the .gguf extension.";
          });
          return;
        }

        setState(() {
          _isModelLoading = true;
          _translatedText = "Model initialization...";
        });

        if (_engine != null) {
          await _engine!.dispose();
        }

        final engine = LlamaEngine(LlamaBackend());
        await engine.loadModel(path);

        setState(() {
          _modelPath = path;
          _engine = engine;
          _translatedText =
              "The model has been successfully loaded and is ready for use!";
        });

        if (_inputController.text.trim().isNotEmpty) {
          _translate();
        }
      }
    } catch (e) {
      setState(() {
        _translatedText = "Model loading error: $e";
      });
    } finally {
      setState(() {
        _isModelLoading = false;
      });
    }
  }

  Future<void> _translate() async {
    if (_engine == null || _inputController.text.trim().isEmpty) return;

    setState(() {
      _isTranslating = true;
      _translatedText = "";
    });

    final prompt =
        """
System: You are a professional translator. Translate the text directly without any introduction, explanations, or quotes.
Task: Translate from $_sourceLang to $_targetLang.
Text: ${_inputController.text}
Translation:""";

    try {
      final tokenStream = _engine!.generate(prompt);

      await for (final token in tokenStream) {
        setState(() {
          _translatedText += token;
        });
      }
    } catch (e) {
      setState(() {
        _translatedText = "Inference error: $e";
      });
    } finally {
      setState(() {
        _isTranslating = false;
      });
    }
  }

  void _reverseLanguages() {
    setState(() {
      final temp = _sourceLang;
      _sourceLang = _targetLang;
      _targetLang = temp;
    });
  }

  Widget _buildLanguageSelector({
    required String selectedLanguage,
    required Function(String) onSelected,
  }) {
    return SearchAnchor(
      builder: (BuildContext context, SearchController controller) {
        return ElevatedButton.icon(
          onPressed: () => controller.openView(),
          icon: const Icon(Icons.language, size: 18),
          label: Text(selectedLanguage, overflow: TextOverflow.ellipsis),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
        );
      },
      suggestionsBuilder: (BuildContext context, SearchController controller) {
        final String keyword = controller.text.toLowerCase();

        return _languages
            .where((lang) => lang.toLowerCase().contains(keyword))
            .map(
              (lang) => ListTile(
                title: Text(lang),
                trailing: lang == selectedLanguage
                    ? const Icon(Icons.check, color: Colors.deepPurple)
                    : null,
                onTap: () {
                  onSelected(lang);
                  controller.closeView(lang);
                },
              ),
            )
            .toList();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local GGUF Translator'),
        actions: [
          if (_isModelLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isModelLoading || _isTranslating
                            ? null
                            : _pickAndLoadModel,
                        icon: const Icon(Icons.file_open),
                        label: const Text("Choose .GGUF model"),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _modelPath != null
                            ? "Loaded: ${_modelPath!.split('/').last}"
                            : "Model not selected (use GGUF, for example, translategemma-4b-it.Q4_K_S.gguf)",
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: _buildLanguageSelector(
                      selectedLanguage: _sourceLang,
                      onSelected: (val) => setState(() => _sourceLang = val),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.swap_horiz,
                      size: 28,
                      color: Colors.deepPurple,
                    ),
                    onPressed: _reverseLanguages,
                    tooltip: 'Reverse languages',
                  ),
                  Expanded(
                    child: _buildLanguageSelector(
                      selectedLanguage: _targetLang,
                      onSelected: (val) => setState(() => _targetLang = val),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _inputController,
                maxLines: 4,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Type text for translation...',
                ),
              ),
              const SizedBox(height: 12),

              ElevatedButton(
                onPressed:
                    (_engine == null || _isTranslating || _isModelLoading)
                    ? null
                    : _translate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                ),
                child: _isTranslating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Translate"),
              ),
              const SizedBox(height: 16),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Текстовое поле занимает все доступное пространство
                    Expanded(
                      child: Text(
                        _translatedText.isEmpty
                            ? "Translation will be here..."
                            : _translatedText,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    // Кнопка копирования показывается только когда есть текст
                    if (_translatedText.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: 'Copy translation',
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _translatedText),
                          );
                          // Опционально: показать уведомление об успехе
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Translation copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
