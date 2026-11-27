/// Strongly typed conversation entry used by the chat transcript.
class ChatMessage {
  final String role;
  final String text;
  final bool showActions;

  const ChatMessage({
    required this.role,
    required this.text,
    this.showActions = false,
  });

  const ChatMessage.user(String text)
      : this(role: 'user', text: text);
  const ChatMessage.agent(String text, {bool showActions = false})
      : this(role: 'agent', text: text, showActions: showActions);

  bool get isUser => role == 'user';
}
