import 'dart:convert';

class MockData {
  static const String _devicesJson = '''
  [
    {
      "id": "DEV001",
      "name": "Smart Hub Alpha",
      "profilePhotoUrl": "https://i.pravatar.cc/150?u=a042581f4e29026704d",
      "lastMessage": "System updated successfully.",
      "timestamp": "2023-10-27T10:00:00Z"
    },
    {
      "id": "DEV002",
      "name": "Sensor Node Beta",
      "profilePhotoUrl": "https://i.pravatar.cc/150?u=a042581f4e29026024d",
      "lastMessage": "Battery level at 80%",
      "timestamp": "2023-10-26T14:30:00Z"
    },
    {
      "id": "DEV003",
      "name": "Camera Gamma",
      "profilePhotoUrl": "https://i.pravatar.cc/150?u=a04258a2462d826712d",
      "lastMessage": "Motion detected at front door.",
      "timestamp": "2023-10-27T09:15:00Z"
    }
  ]
  ''';

  static const String _messagesJson = '''
  {
    "DEV001": [
      {
        "id": "msg1",
        "text": "Hello, I am Smart Hub Alpha. How can I help?",
        "timestamp": "2023-10-27T09:55:00Z",
        "isUser": false
      },
      {
        "id": "msg2",
        "text": "Update system software.",
        "timestamp": "2023-10-27T09:58:00Z",
        "isUser": true
      },
      {
        "id": "msg3",
        "text": "System updated successfully.",
        "timestamp": "2023-10-27T10:00:00Z",
        "isUser": false
      }
    ],
    "DEV002": [
      {
        "id": "msg4",
        "text": "Sensor Node Beta online. Battery level at 80%",
        "timestamp": "2023-10-26T14:30:00Z",
        "isUser": false
      }
    ],
    "DEV003": [
      {
        "id": "msg5",
        "text": "Motion detected at front door.",
        "timestamp": "2023-10-27T09:15:00Z",
        "isUser": false
      }
    ]
  }
  ''';

  static List<Map<String, dynamic>> getDevices() {
    final List<dynamic> parsedList = json.decode(_devicesJson);
    return parsedList.cast<Map<String, dynamic>>();
  }

  static Map<String, List<Map<String, dynamic>>> getMessages() {
    final Map<String, dynamic> parsedMap = json.decode(_messagesJson);
    return parsedMap.map((key, value) => MapEntry(key, (value as List<dynamic>).cast<Map<String, dynamic>>()));
  }
}
