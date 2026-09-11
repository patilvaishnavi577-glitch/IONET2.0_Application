import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/providers/support_provider.dart';
import '../../core/utils/app_feedback.dart';
import 'knowledge_device_model.dart';
import 'knowledge_channel_screen.dart';

class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key});

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<SupportProvider>(context, listen: false);
      provider.fetchChannels();
      provider.fetchSubscribedChannels();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SupportProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.channels.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.error != null && provider.channels.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(provider.error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    provider.fetchChannels();
                    provider.fetchSubscribedChannels();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final allDevices = provider.channels;
        final followingDevices = allDevices.where((d) => provider.isFollowing(d.id)).toList();
        final recommendedDevices = allDevices.where((d) => !provider.isFollowing(d.id)).toList();

        final List<Widget> listItems = [];

        if (followingDevices.isNotEmpty) {
          listItems.add(
            const Padding(
              padding: EdgeInsets.only(top: 8.0, bottom: 12.0),
              child: Text(
                'Following',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          );
          for (var device in followingDevices) {
            listItems.add(_buildChannelTile(device, provider));
          }
        }

        if (recommendedDevices.isNotEmpty) {
          listItems.add(
            const Padding(
              padding: EdgeInsets.only(top: 16.0, bottom: 12.0),
              child: Text(
                'Find Channels',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          );
          for (var device in recommendedDevices) {
            listItems.add(_buildChannelTile(device, provider));
          }
        }

        if (listItems.isEmpty) {
          return const Center(
            child: Text(
              'No channels available.',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16.0),
          children: listItems,
        );
      },
    );
  }

  Widget _buildChannelTile(KnowledgeDevice device, SupportProvider provider) {
    final isFollowing = provider.isFollowing(device.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => KnowledgeChannelScreen(channel: device),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  Icons.memory_rounded, 
                  size: 26, 
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name, 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${device.followers} followers', 
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isFollowing) ...[
                TextButton(
                  onPressed: () async {
                    try {
                      await provider.followChannel(device.id);
                    } catch (e) {
                      if (mounted) {
                        AppFeedback.showError(context, e);
                      }
                    }
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF00A884),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text(
                    'Follow',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Icon(
                Icons.chevron_right_rounded, 
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
