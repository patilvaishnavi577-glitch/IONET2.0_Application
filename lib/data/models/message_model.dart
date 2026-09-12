class MessageModel {
  final String id;
  final String text;
  final String? command;
  final DateTime timestamp;
  final bool isUser;
  final Map<String, dynamic>? rawData;
  final bool isEditable;
  final bool? isSuccess;
  final String? responseCommand;

  MessageModel({
    required this.id,
    required this.text,
    this.command,
    required this.timestamp,
    required this.isUser,
    this.rawData,
    this.isEditable = false,
    this.isSuccess,
    this.responseCommand,
  });

  MessageModel copyWith({
    String? id,
    String? text,
    String? command,
    DateTime? timestamp,
    bool? isUser,
    Map<String, dynamic>? rawData,
    bool? isEditable,
    bool? isSuccess,
    String? responseCommand,
  }) {
    return MessageModel(
      id: id ?? this.id,
      text: text ?? this.text,
      command: command ?? this.command,
      timestamp: timestamp ?? this.timestamp,
      isUser: isUser ?? this.isUser,
      rawData: rawData ?? (this.rawData != null ? Map<String, dynamic>.from(this.rawData!) : null),
      isEditable: isEditable ?? this.isEditable,
      isSuccess: isSuccess ?? this.isSuccess,
      responseCommand: responseCommand ?? this.responseCommand,
    );
  }

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'],
      text: json['text'],
      command: json['command'],
      timestamp: DateTime.parse(json['timestamp']),
      isUser: json['isUser'],
      rawData: json['rawData'] != null ? Map<String, dynamic>.from(json['rawData']) : null,
      isEditable: json['isEditable'] as bool? ?? false,
      isSuccess: json['isSuccess'] as bool?,
      responseCommand: json['responseCommand'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      if (command != null) 'command': command,
      'timestamp': timestamp.toIso8601String(),
      'isUser': isUser,
      if (rawData != null) 'rawData': rawData,
      if (isEditable) 'isEditable': isEditable,
      if (isSuccess != null) 'isSuccess': isSuccess,
      if (responseCommand != null) 'responseCommand': responseCommand,
    };
  }
}

