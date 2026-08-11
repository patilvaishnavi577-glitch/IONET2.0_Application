import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/providers/support_provider.dart';
import 'knowledge_device_model.dart';

class KnowledgeChannelScreen extends StatelessWidget {
  final KnowledgeDevice channel;

  const KnowledgeChannelScreen({super.key, required this.channel});

  void _launchUrl(BuildContext context, String title, String url) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening $title: $url')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supportProvider = Provider.of<SupportProvider>(context);
    final activeChannel = supportProvider.channels.firstWhere(
      (c) => c.id == channel.id,
      orElse: () => channel,
    );
    final isFollowing = supportProvider.isFollowing(activeChannel.id);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(Icons.memory_rounded, size: 20, color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(activeChannel.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('${activeChannel.followers} followers', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                if (isFollowing) {
                  await supportProvider.unfollowChannel(activeChannel.id);
                } else {
                  await supportProvider.followChannel(activeChannel.id);
                }
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Action failed: $e')),
                );
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: isFollowing 
                  ? (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87) 
                  : const Color(0xFF00A884),
            ),
            child: Text(
              isFollowing ? 'Unfollow' : 'Follow',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // A channel feed post
            _buildPost(
              context,
              date: 'Today',
              text: channel.description,
              isFirst: true,
            ),
            ...channel.topics.map((topic) {
              IconData icon = Icons.link;
              Color color = Colors.blue;
              if (topic.link.contains('youtube.com') || topic.link.contains('youtu.be')) {
                icon = Icons.play_circle_fill;
                color = Colors.red;
              } else if (topic.link.toLowerCase().endsWith('.pdf') || topic.link.toLowerCase().contains('.pdf')) {
                icon = Icons.picture_as_pdf;
                color = Colors.orange;
              }
              return _buildPostCard(
                context,
                icon: icon,
                color: color,
                title: topic.name,
                url: topic.link,
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPost(BuildContext context, {required String date, required String text, bool isFirst = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (isFirst) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              date, 
              style: TextStyle(
                fontSize: 12, 
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16, right: 48),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Text(
              text, 
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPostCard(BuildContext context, {required IconData icon, required Color color, required String title, required String url}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16, right: 48),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
            width: 1,
          ),
        ),
        clipBehavior: Clip.hardEdge,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _launchUrl(context, title, url),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title, 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          url, 
                          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13, fontWeight: FontWeight.w500), 
                          maxLines: 1, 
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
