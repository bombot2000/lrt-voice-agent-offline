/// Strongly typed conversation entry used by the chat transcript.
class ChatMessage {
  final String role;
  final String text;

  const ChatMessage({required this.role, required this.text});

  const ChatMessage.user(String text) : this(role: 'user', text: text);
  const ChatMessage.agent(String text) : this(role: 'agent', text: text);

  bool get isUser => role == 'user';
}
