import '../../core/api_config.dart';

class DeviceModel {
  final String id;
  final String name;
  final String profilePhotoUrl;
  final String lastMessage;
  final DateTime timestamp;
  final bool isOwner;

  DeviceModel({
    required this.id,
    required this.name,
    required this.profilePhotoUrl,
    required this.lastMessage,
    required this.timestamp,
    this.isOwner = true,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    final String parsedId = json['deviceId'] as String? ?? json['id'] as String? ?? '';
    final String accessType = json['accessType'] as String? ?? 'OWNER';
    final bool isOwner = accessType == 'OWNER';

    final String rawImage = json['deviceImage'] as String? ?? 
                            json['profilePhotoUrl'] as String? ?? '';
    
    String parsedPhotoUrl = '';
    if (rawImage.isNotEmpty) {
      if (rawImage.startsWith('http://') || rawImage.startsWith('https://')) {
        parsedPhotoUrl = rawImage;
      } else {
        final baseUrl = ApiConfig.baseUrl;
        final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
        final cleanRawImage = rawImage.startsWith('/') ? rawImage : '/$rawImage';
        parsedPhotoUrl = '$cleanBaseUrl$cleanRawImage';
      }
    } else {
      parsedPhotoUrl = '';
    }

    return DeviceModel(
      id: parsedId,
      name: json['deviceName'] as String? ?? json['name'] as String? ?? 'Unnamed Device',
      profilePhotoUrl: parsedPhotoUrl,
      lastMessage: json['lastMessage'] as String? ?? 'No messages yet',
      timestamp: json['lastSeen'] != null 
          ? DateTime.parse(json['lastSeen'] as String) 
          : (json['timestamp'] != null 
              ? DateTime.parse(json['timestamp'] as String) 
              : (json['updatedAt'] != null 
                  ? DateTime.parse(json['updatedAt'] as String) 
                  : DateTime.now())),
      isOwner: isOwner,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'profilePhotoUrl': profilePhotoUrl,
      'lastMessage': lastMessage,
      'timestamp': timestamp.toIso8601String(),
      'isOwner': isOwner,
    };
  }

  DeviceModel copyWith({
    String? id,
    String? name,
    String? profilePhotoUrl,
    String? lastMessage,
    DateTime? timestamp,
    bool? isOwner,
  }) {
    return DeviceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      timestamp: timestamp ?? this.timestamp,
      isOwner: isOwner ?? this.isOwner,
    );
  }
}
