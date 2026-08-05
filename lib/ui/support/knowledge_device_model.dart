class ChannelTopic {
  final String id;
  final String name;
  final String link;

  ChannelTopic({
    required this.id,
    required this.name,
    required this.link,
  });

  factory ChannelTopic.fromJson(Map<String, dynamic> json) {
    return ChannelTopic(
      id: json['id'] as String? ?? '',
      name: json['topicName'] as String? ?? json['name'] as String? ?? '',
      link: json['link'] as String? ?? '',
    );
  }
}

class KnowledgeDevice {
  final String id;
  final String name;
  final String description;
  final String followers;
  final List<ChannelTopic> topics;

  KnowledgeDevice({
    required this.id,
    required this.name,
    required this.description,
    required this.followers,
    required this.topics,
  });

  factory KnowledgeDevice.fromJson(Map<String, dynamic> json) {
    final rawTopics = json['topics'] as List? ?? [];
    final parsedTopics = rawTopics.map((t) => ChannelTopic.fromJson(t)).toList();
    
    // Simulate followers count deterministically based on channel id hash
    final int hash = (json['id'] as String? ?? '').hashCode.abs();
    final String followersCount = '${(hash % 900 + 100)}K';

    return KnowledgeDevice(
      id: json['id'] as String? ?? '',
      name: json['channelName'] as String? ?? json['name'] as String? ?? '',
      description: json['description'] as String? ?? 'Stay updated on industrial automation and IoT trends.',
      followers: followersCount,
      topics: parsedTopics,
    );
  }
}
