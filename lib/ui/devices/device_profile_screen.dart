import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/providers/device_provider.dart';
import '../../data/models/device_model.dart';

class DeviceProfileScreen extends StatefulWidget {
  final String deviceId;

  const DeviceProfileScreen({super.key, required this.deviceId});

  @override
  State<DeviceProfileScreen> createState() => _DeviceProfileScreenState();
}

class _DeviceProfileScreenState extends State<DeviceProfileScreen> {
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DeviceProvider>(context, listen: false)
          .fetchDeviceDetails(widget.deviceId);
    });
  }

  Future<void> _pickAndUploadImage(DeviceModel device) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final provider = Provider.of<DeviceProvider>(context, listen: false);

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() => _isLoading = true);
      await provider.uploadDeviceImage(device.id, pickedFile.path);

      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Device picture updated successfully')),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error uploading image: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteImage(DeviceModel device) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final provider = Provider.of<DeviceProvider>(context, listen: false);

    try {
      setState(() => _isLoading = true);
      await provider.deleteDeviceImage(device.id);

      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Device picture deleted successfully')),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error removing image: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showEditNameDialog(BuildContext context, DeviceModel device) {
    final controller = TextEditingController(text: device.name);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Change Device Name'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Device Name',
                hintText: 'Enter new device name',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Device name cannot be empty';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  final newName = controller.text.trim();
                  Navigator.pop(context);
                  
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  setState(() => _isLoading = true);
                  
                  try {
                    await Provider.of<DeviceProvider>(context, listen: false)
                        .updateDeviceName(device.id, newName);
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(content: Text('Device name updated successfully')),
                    );
                  } catch (e) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(content: Text('Failed to update device name: $e')),
                    );
                  } finally {
                    if (mounted) {
                      setState(() => _isLoading = false);
                    }
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showShareDeviceDialog(DeviceModel device) {
    final provider = Provider.of<DeviceProvider>(context, listen: false);
    final searchController = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];
    Map<String, dynamic>? selectedUser;
    bool isSearching = false;
    bool isSharing = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Share Device'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        labelText: 'Search user by email or phone no.',
                        labelStyle: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        suffixIcon: isSearching
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.search_rounded),
                                onPressed: () async {
                                  if (searchController.text.trim().isEmpty) return;
                                  setDialogState(() => isSearching = true);
                                  final results = await provider.searchUsers(searchController.text.trim());
                                  setDialogState(() {
                                    searchResults = results;
                                    isSearching = false;
                                  });
                                },
                              ),
                      ),
                      onChanged: (val) async {
                        if (val.trim().length >= 3) {
                          setDialogState(() => isSearching = true);
                          final results = await provider.searchUsers(val.trim());
                          setDialogState(() {
                            searchResults = results;
                            isSearching = false;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    if (searchResults.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: searchResults.length,
                          itemBuilder: (context, index) {
                            final user = searchResults[index];
                            final name = user['name'] as String? ?? 'Unnamed User';
                            final email = user['email'] as String? ?? '';
                            final isSelected = selectedUser?['id'] == user['id'];

                            return ListTile(
                              title: Text(name),
                              subtitle: Text(email),
                              selected: isSelected,
                              trailing: isSelected ? const Icon(Icons.check, color: Colors.green) : null,
                              onTap: () {
                                setDialogState(() {
                                  selectedUser = user;
                                });
                              },
                            );
                          },
                        ),
                      ),
                    if (selectedUser != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Selected: ${selectedUser!['name']} (${selectedUser!['email']})',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedUser == null || isSharing
                      ? null
                      : () async {
                          setDialogState(() => isSharing = true);
                          try {
                            await provider.shareDevice(device.id, selectedUser!['id'] as String);
                            await provider.fetchDeviceDetails(widget.deviceId);
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Device shared successfully.')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to share device: $e')),
                              );
                            }
                          } finally {
                            setDialogState(() => isSharing = false);
                          }
                        },
                  child: isSharing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Share'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmUnshare(DeviceModel device, String userId, String userName) async {
    final provider = Provider.of<DeviceProvider>(context, listen: false);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Action'),
          content: Text('Are you sure you want to stop sharing this device with $userName?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Stop Sharing', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await provider.unshareDevice(device.id, userId);
        await provider.fetchDeviceDetails(widget.deviceId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unshared successfully.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error unsharing: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  void _showImageOptions(DeviceModel device) {
    if (!device.isOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only the owner can upload or remove device images.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Upload New Image'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage(device);
                },
              ),
              if (device.profilePhotoUrl.isNotEmpty && !device.profilePhotoUrl.contains('i.pravatar.cc'))
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Remove Image', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteImage(device);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Profile'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Consumer<DeviceProvider>(
        builder: (context, provider, child) {
          // Find device from provider list
          final device = provider.devices.firstWhere(
            (d) => d.id == widget.deviceId,
            orElse: () => DeviceModel(
              id: widget.deviceId,
              mongoId: widget.deviceId,
              name: 'Unknown Device',
              profilePhotoUrl: '',
              lastMessage: '',
              timestamp: DateTime.now(),
              isOwner: false,
            ),
          );

          final details = provider.getDeviceDetails(widget.deviceId);
          final isOnline = provider.isDeviceOnline(widget.deviceId);

          String installationDate = 'Unknown';
          if (details != null && details['createdAt'] != null) {
            try {
              final parsedDate = DateTime.parse(details['createdAt'] as String).toLocal();
              final day = parsedDate.day.toString().padLeft(2, '0');
              final month = parsedDate.month.toString().padLeft(2, '0');
              final year = parsedDate.year;
              final hour = parsedDate.hour.toString().padLeft(2, '0');
              final minute = parsedDate.minute.toString().padLeft(2, '0');
              installationDate = '$day/$month/$year, $hour:$minute';
            } catch (e) {
              debugPrint('Error parsing createdAt: $e');
            }
          }

          final String accessType = details?['accessType'] as String? ?? (device.isOwner ? 'OWNER' : 'SHARED');
          final String displayAccessType = accessType.toUpperCase() == 'OWNER'
              ? 'Owned'
              : (accessType.toUpperCase() == 'SHARED' ? 'Shared' : accessType);
          final sharedUsers = details?['sharedUsers'] as List? ?? [];

          return Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    // Device Avatar with Pulsing/Online Dot
                    Center(
                      child: Stack(
                        children: [
                          GestureDetector(
                            onTap: () => _showImageOptions(device),
                            child: Hero(
                              tag: 'avatar-${device.id}',
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: theme.colorScheme.primary.withOpacity(0.2),
                                    width: 4,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: CircleAvatar(
                                  radius: 64,
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  backgroundImage: device.profilePhotoUrl.isNotEmpty
                                      ? NetworkImage(device.profilePhotoUrl) as ImageProvider
                                      : const AssetImage('assets/ionet_logo.png'),
                                ),
                              ),
                            ),
                          ),
                          // Camera Overlay for Owner
                          if (device.isOwner)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () => _showImageOptions(device),
                                child: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: theme.colorScheme.primary,
                                  child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Device Name and Online Status Dot
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            device.name,
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (device.isOwner) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _showEditNameDialog(context, device),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                            tooltip: 'Edit Name',
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOnline ? Colors.green : Colors.red,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isOnline ? 'ONLINE' : 'OFFLINE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isOnline ? Colors.green : Colors.red,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Device Metadata Cards
                    _buildSectionHeader(theme, 'Device Details'),
                    const SizedBox(height: 12),
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            _buildInfoRow(theme, Icons.fingerprint, 'Device ID', device.id),
                            const Divider(height: 24),
                            _buildInfoRow(theme, Icons.security, 'Access Level', displayAccessType),
                            const Divider(height: 24),
                            _buildInfoRow(
                              theme,
                              Icons.calendar_today,
                              'Installation Date',
                              installationDate,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Shared With Section
                    if (device.isOwner) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildSectionHeader(theme, 'Shared Access (${sharedUsers.length})'),
                          IconButton(
                            icon: const Icon(Icons.person_add),
                            color: theme.colorScheme.primary,
                            onPressed: () => _showShareDeviceDialog(device),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (sharedUsers.isEmpty)
                        Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                            child: Center(
                              child: Text(
                                'This device is not shared with anyone.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: sharedUsers.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final user = sharedUsers[index] as Map;
                            final name = user['name'] as String? ?? 'Unnamed User';
                            final email = user['email'] as String? ?? 'No Email';
                            return Card(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: theme.colorScheme.secondaryContainer,
                                  child: Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                    style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
                                  ),
                                ),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(email),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => _confirmUnshare(device, user['id'] as String? ?? '', name),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ],
                ),
              ),
              if (_isLoading)
                Container(
                  color: Colors.black.withOpacity(0.3),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary.withOpacity(0.8), size: 22),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
