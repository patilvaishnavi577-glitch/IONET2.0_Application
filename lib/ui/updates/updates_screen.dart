import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api_config.dart';

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

class UpdateModel {
  final String id;
  final String title;
  final String description;
  final List<String> files;
  final DateTime createdAt;

  UpdateModel({
    required this.id,
    required this.title,
    required this.description,
    required this.files,
    required this.createdAt,
  });

  factory UpdateModel.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['mediaUrls'] as List? ?? json['files'] as List? ?? [];
    final List<String> parsedFiles = [];
    for (var f in rawFiles) {
      if (f is String) {
        if (f.startsWith('http://') || f.startsWith('https://')) {
          parsedFiles.add(f);
        } else {
          final baseUrl = ApiConfig.baseUrl;
          final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
          final cleanF = f.startsWith('/') ? f : '/$f';
          parsedFiles.add('$cleanBase$cleanF');
        }
      }
    }

    return UpdateModel(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      title: json['title'] as String? ?? 'No Title',
      description: json['description'] as String? ?? 'No Description',
      files: parsedFiles,
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt'] as String) 
          : DateTime.now(),
    );
  }
}



// -----------------------------------------------------------------------------
// Custom Painter for Segmented Status Ring
// -----------------------------------------------------------------------------

class StatusPainter extends CustomPainter {
  final bool isViewed;
  final int segmentCount;

  StatusPainter({
    required this.isViewed,
    required this.segmentCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double strokeWidth = 2.5;
    final Paint paint = Paint()
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (isViewed) {
      paint.color = Colors.grey.shade400;
      canvas.drawCircle(size.center(Offset.zero), size.width / 2 - strokeWidth, paint);
      return;
    }

    paint.color = const Color(0xFF00A884); // WhatsApp Green

    if (segmentCount <= 1) {
      canvas.drawCircle(size.center(Offset.zero), size.width / 2 - strokeWidth, paint);
    } else {
      final double spacing = 0.09; // Gap size in radians
      final double totalAngle = 2 * pi;
      final double segmentAngle = (totalAngle / segmentCount) - spacing;

      for (int i = 0; i < segmentCount; i++) {
        final double startAngle = -pi / 2 + i * (totalAngle / segmentCount) + (spacing / 2);
        canvas.drawArc(
          Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - strokeWidth),
          startAngle,
          segmentAngle,
          false,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class StatusRing extends StatelessWidget {
  final Widget child;
  final bool isViewed;
  final int segmentCount;

  const StatusRing({
    super.key,
    required this.child,
    required this.isViewed,
    this.segmentCount = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: CustomPaint(
        painter: StatusPainter(
          isViewed: isViewed,
          segmentCount: segmentCount,
        ),
        child: Padding(
          padding: const EdgeInsets.all(4.5),
          child: ClipOval(
            child: child,
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Main Updates Screen
// -----------------------------------------------------------------------------

class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key});

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  List<UpdateModel> _updates = [];
  Set<String> _viewedUpdateIds = {};
  bool _isLoading = true;
  String? _errorMsg;
  bool _viewedExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadStateAndFetch();
  }

  Future<void> _loadStateAndFetch() async {
    await _loadSavedStates();
    await _fetchUpdates();
  }

  Future<void> _loadSavedStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load viewed update IDs
      final List<String>? viewed = prefs.getStringList('viewed_updates_ids');
      if (viewed != null) {
        setState(() {
          _viewedUpdateIds = viewed.toSet();
        });
      }
    } catch (e) {
      debugPrint('Error loading saved states: $e');
    }
  }

  Future<void> _fetchUpdates() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/updates');
    debugPrint('--> [API REQUEST] GET $url');

    try {
      final response = await http.get(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      debugPrint('<-- [API RESPONSE] ${response.statusCode} GET $url');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<UpdateModel> temp = [];
        
        final rawList = (decoded is Map && decoded['data'] is List)
            ? decoded['data'] as List
            : (decoded is List ? decoded : []);

        for (var item in rawList) {
          if (item is Map<String, dynamic>) {
            temp.add(UpdateModel.fromJson(item));
          }
        }

        temp.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (mounted) {
          setState(() {
            _updates = temp;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMsg = 'Failed to fetch updates: Status ${response.statusCode}';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching updates: $e');
      if (mounted) {
        setState(() {
          _errorMsg = 'Error connecting to server. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markUpdateAsViewed(String updateId) async {
    if (_viewedUpdateIds.contains(updateId)) return;
    setState(() {
      _viewedUpdateIds.add(updateId);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('viewed_updates_ids', _viewedUpdateIds.toList());
    } catch (e) {
      debugPrint('Error saving viewed state: $e');
    }
  }


  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else {
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    }
  }


  void _openUpdateViewer(UpdateModel update) {
    _markUpdateAsViewed(update.id);

    // Build story slides
    final List<StoryItem> stories = [];

    // Slide 1: Title and Description in Text format
    stories.add(
      StoryItem(
        type: StoryType.text,
        text: '${update.title}\n\n${update.description}',
        backgroundColor: const Color(0xFF2A3942),
        timestamp: update.createdAt,
        attachments: update.files.where((f) {
          final lower = f.toLowerCase();
          return !(lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg') ||
              lower.endsWith('.png') ||
              lower.endsWith('.gif') ||
              lower.endsWith('.webp'));
        }).toList(),
      ),
    );

    // Filter image media
    final images = update.files.where((f) {
      final lower = f.toLowerCase();
      return lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.gif') ||
          lower.endsWith('.webp');
    }).toList();

    for (var img in images) {
      stories.add(
        StoryItem(
          type: StoryType.image,
          text: update.title,
          imageUrl: img,
          timestamp: update.createdAt,
        ),
      );
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StatusStoryViewer(
          title: update.title,
          subtitle: _formatTimeAgo(update.createdAt),
          avatar: null,
          stories: stories,
        ),
      ),
    ).then((_) {
      // Re-trigger load from SharedPreferences to update UI lists
      _loadSavedStates();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Separate updates into viewed and recent
    final recentUpdates = _updates.where((u) => !_viewedUpdateIds.contains(u.id)).toList();
    final viewedUpdates = _updates.where((u) => _viewedUpdateIds.contains(u.id)).toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _fetchUpdates,
        color: theme.colorScheme.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Recent Updates Header
            if (!_isLoading && _errorMsg == null && recentUpdates.isNotEmpty)
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: isDark ? const Color(0xFF111B21) : Colors.grey.shade50,
                  child: Text(
                    'Recent updates',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFF00A884) : const Color(0xFF00A884),
                    ),
                  ),
                ),
              ),

            // Recent Updates List
            if (!_isLoading && _errorMsg == null && recentUpdates.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final update = recentUpdates[index];
                    final imagesCount = update.files.where((f) {
                      final lower = f.toLowerCase();
                      return lower.endsWith('.jpg') ||
                          lower.endsWith('.jpeg') ||
                          lower.endsWith('.png') ||
                          lower.endsWith('.gif') ||
                          lower.endsWith('.webp');
                    }).length;
                    
                    // Total segments = 1 text slide + image count
                    final totalSegments = 1 + imagesCount;

                    return _buildStatusItemTile(
                      update: update,
                      isViewed: false,
                      segmentCount: totalSegments,
                      theme: theme,
                      isDark: isDark,
                    );
                  },
                  childCount: recentUpdates.length,
                ),
              ),

            // Viewed Updates Header (Collapsible)
            if (!_isLoading && _errorMsg == null && viewedUpdates.isNotEmpty)
              SliverToBoxAdapter(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _viewedExpanded = !_viewedExpanded;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: isDark ? const Color(0xFF111B21) : Colors.grey.shade50,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Viewed updates',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        Icon(
                          _viewedExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          size: 18,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Viewed Updates List
            if (!_isLoading && _errorMsg == null && viewedUpdates.isNotEmpty && _viewedExpanded)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final update = viewedUpdates[index];
                    return _buildStatusItemTile(
                      update: update,
                      isViewed: true,
                      segmentCount: 1,
                      theme: theme,
                      isDark: isDark,
                    );
                  },
                  childCount: viewedUpdates.length,
                ),
              ),

            // Empty & Loading & Error Handling
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMsg != null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 54, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(
                          _errorMsg!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _fetchUpdates,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_updates.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.system_update_alt_rounded,
                        size: 72,
                        color: theme.colorScheme.primary.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No Status Updates Found',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Check back later for firmware updates.',
                        style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItemTile({
    required UpdateModel update,
    required bool isViewed,
    required int segmentCount,
    required ThemeData theme,
    required bool isDark,
  }) {
    // Find first image for avatar preview
    final firstImg = update.files.firstWhere(
      (f) {
        final lower = f.toLowerCase();
        return lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.png') ||
            lower.endsWith('.gif') ||
            lower.endsWith('.webp');
      },
      orElse: () => '',
    );

    return ListTile(
      onTap: () => _openUpdateViewer(update),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: StatusRing(
        isViewed: isViewed,
        segmentCount: segmentCount,
        child: firstImg.isNotEmpty
            ? Image.network(
                firstImg,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.system_update_rounded, color: theme.colorScheme.primary),
                ),
              )
            : Container(
                color: isDark ? const Color(0xFF2A3942) : theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.system_update_rounded,
                  color: isDark ? Colors.white70 : theme.colorScheme.primary,
                  size: 24,
                ),
              ),
      ),
      title: Text(
        update.title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Text(
          _formatTimeAgo(update.createdAt),
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ),
    );
  }
}



// -----------------------------------------------------------------------------
// Custom Status Story Viewer Widget (Full-Screen)
// -----------------------------------------------------------------------------

enum StoryType { text, image }

class StoryItem {
  final StoryType type;
  final String text;
  final String? imageUrl;
  final Color? backgroundColor;
  final DateTime? timestamp;
  final List<String> attachments; // Attached files that are non-images

  StoryItem({
    required this.type,
    required this.text,
    this.imageUrl,
    this.backgroundColor,
    this.timestamp,
    this.attachments = const [],
  });
}

class StatusStoryViewer extends StatefulWidget {
  final String title;
  final String subtitle;
  final String? avatar;
  final List<StoryItem> stories;
  final VoidCallback? onDelete; // If set, displays a delete button for custom status

  const StatusStoryViewer({
    super.key,
    required this.title,
    required this.subtitle,
    required this.stories,
    this.avatar,
    this.onDelete,
  });

  @override
  State<StatusStoryViewer> createState() => _StatusStoryViewerState();
}

class _StatusStoryViewerState extends State<StatusStoryViewer> with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextStory();
      }
    });

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _nextStory() {
    if (_currentIndex < widget.stories.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _animController.reset();
      _animController.forward();
    } else {
      Navigator.pop(context);
    }
  }

  void _previousStory() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _animController.reset();
      _animController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.stories[_currentIndex];
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onLongPressStart: (_) {
          _animController.stop();
        },
        onLongPressEnd: (_) {
          _animController.forward();
        },
        onVerticalDragUpdate: (details) {
          // Swipe down to close
          if (details.delta.dy > 12) {
            Navigator.pop(context);
          }
        },
        onTapUp: (details) {
          final double tapPositionX = details.globalPosition.dx;
          if (tapPositionX < size.width * 0.3) {
            _previousStory();
          } else {
            _nextStory();
          }
        },
        child: Stack(
          children: [
            // Slide Background/Image Content
            Positioned.fill(
              child: _buildStoryContent(story),
            ),

            // Top Status Bar Overlay (Gradient for readability)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 120,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black54, Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),

            // Progress Indicators
            Positioned(
              top: 50,
              left: 12,
              right: 12,
              child: Row(
                children: List.generate(
                  widget.stories.length,
                  (index) => Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2.0),
                      height: 3.5,
                      child: AnimatedBuilder(
                        animation: _animController,
                        builder: (context, child) {
                          double progress = 0.0;
                          if (index < _currentIndex) {
                            progress = 1.0;
                          } else if (index == _currentIndex) {
                            progress = _animController.value;
                          }
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.white.withOpacity(0.35),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Top User Info (Avatar, Name, Timestamp)
            Positioned(
              top: 66,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: widget.avatar != null && widget.avatar!.isNotEmpty
                        ? NetworkImage(widget.avatar!)
                        : null,
                    backgroundColor: Colors.grey[800],
                    child: widget.avatar == null || widget.avatar!.isEmpty
                        ? const Icon(Icons.person, color: Colors.white70)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.white70),
                      onPressed: () {
                        _animController.stop();
                        showDialog(
                          context: context,
                          builder: (dialogCtx) => AlertDialog(
                            title: const Text('Delete status?'),
                            content: const Text('This will delete all your custom statuses.'),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(dialogCtx);
                                  _animController.forward();
                                },
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(dialogCtx);
                                  widget.onDelete!();
                                },
                                child: const Text('Delete', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 26),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryContent(StoryItem story) {
    if (story.type == StoryType.text) {
      return Container(
        color: story.backgroundColor ?? const Color(0xFF00A884),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 100),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              story.text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                height: 1.4,
              ),
            ),
            if (story.attachments.isNotEmpty) ...[
              const SizedBox(height: 48),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'System Attachments:',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              ...story.attachments.map((fileUrl) {
                final fileName = fileUrl.split('/').last;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.insert_drive_file, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          fileName.length > 25 ? '${fileName.substring(0, 22)}...' : fileName,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                      const Icon(Icons.download, color: Colors.white70, size: 18),
                    ],
                  ),
                );
              }),
            ]
          ],
        ),
      );
    } else {
      return Stack(
        alignment: Alignment.center,
        children: [
          // Loader while fetching image
          const Center(child: CircularProgressIndicator(color: Colors.white)),
          // Main Image
          if (story.imageUrl != null)
            Positioned.fill(
              child: Image.network(
                story.imageUrl!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.black87,
                  child: const Center(
                    child: Icon(Icons.broken_image, size: 64, color: Colors.white38),
                  ),
                ),
              ),
            ),


        ],
      );
    }
  }
}
