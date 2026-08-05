class MessageModel {
  final String id;
  final String text;
  final DateTime timestamp;
  final bool isUser;

  MessageModel({
    required this.id,
    required this.text,
    required this.timestamp,
    required this.isUser,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'],
      text: json['text'],
      timestamp: DateTime.parse(json['timestamp']),
      isUser: json['isUser'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'isUser': isUser,
    };
  }
}
