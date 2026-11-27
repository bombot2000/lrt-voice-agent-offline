import 'answer_engine.dart' show Choice;

/// Strongly typed conversation entry used by the chat transcript.
class ChatMessage {
  final String role;
  final String text;
  final bool showActions;
  final List<Choice> choices;

  const ChatMessage({
    required this.role,
    required this.text,
    this.showActions = false,
    this.choices = const [],
  });

  const ChatMessage.user(String text)
      : this(role: 'user', text: text);
  const ChatMessage.agent(
    String text, {
    bool showActions = false,
    List<Choice> choices = const [],
  }) : this(
          role: 'agent',
          text: text,
          showActions: showActions,
          choices: choices,
        );

  bool get isUser => role == 'user';
}
