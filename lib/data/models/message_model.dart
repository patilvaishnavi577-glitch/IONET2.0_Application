class MessageModel {
  final String id;
  final String text;
  final String? command;
  final DateTime timestamp;
  final bool isUser;

  MessageModel({
    required this.id,
    required this.text,
    this.command,
    required this.timestamp,
    required this.isUser,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'],
      text: json['text'],
      command: json['command'],
      timestamp: DateTime.parse(json['timestamp']),
      isUser: json['isUser'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      if (command != null) 'command': command,
      'timestamp': timestamp.toIso8601String(),
      'isUser': isUser,
    };
  }
}
