import 'package:flutter/material.dart';

/// Notification service for handling alerts and notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final List<AppNotification> _notifications = [];
  final List<Function(AppNotification)> _listeners = [];

  /// Get all notifications
  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  /// Get unread notifications count
  int get unreadCount =>
      _notifications.where((n) => !n.isRead).length;

  /// Add a listener for new notifications
  void addListener(Function(AppNotification) listener) {
    _listeners.add(listener);
  }

  /// Remove a listener
  void removeListener(Function(AppNotification) listener) {
    _listeners.remove(listener);
  }

  /// Add a notification
  void addNotification(AppNotification notification) {
    _notifications.insert(0, notification);
    for (var listener in _listeners) {
      listener(notification);
    }
  }

  /// Mark notification as read
  void markAsRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index != -1) {
      _notifications[index] = _notifications[index].copyWith(isRead: true);
    }
  }

  /// Mark all notifications as read
  void markAllAsRead() {
    for (var i = 0; i < _notifications.length; i++) {
      _notifications[i] = _notifications[i].copyWith(isRead: true);
    }
  }

  /// Clear all notifications
  void clearAll() {
    _notifications.clear();
  }

  /// Remove a specific notification
  void remove(String id) {
    _notifications.removeWhere((n) => n.id == id);
  }

  /// Show a snackbar notification
  static void showSnackBar(
    BuildContext context,
    String message, {
    NotificationType type = NotificationType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    Color backgroundColor;
    IconData icon;

    switch (type) {
      case NotificationType.success:
        backgroundColor = Colors.green;
        icon = Icons.check_circle;
        break;
      case NotificationType.error:
        backgroundColor = Colors.red;
        icon = Icons.error;
        break;
      case NotificationType.warning:
        backgroundColor = Colors.orange;
        icon = Icons.warning;
        break;
      case NotificationType.anomaly:
        backgroundColor = Colors.red[700]!;
        icon = Icons.warning_amber;
        break;
      default:
        backgroundColor = Colors.blue;
        icon = Icons.info;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  /// Show a dialog notification
  static void showNotificationDialog(
    BuildContext context,
    AppNotification notification,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              notification.type.icon,
              color: notification.type.color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(notification.title),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.message),
            if (notification.actionLabel != null) ...[
              const SizedBox(height: 16),
              Text(
                'Action: ${notification.actionLabel}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (notification.onDismiss != null)
            TextButton(
              onPressed: () {
                notification.onDismiss?.call();
                Navigator.pop(context);
              },
              child: const Text('Dismiss'),
            ),
          if (notification.onAction != null && notification.actionLabel != null)
            ElevatedButton(
              onPressed: () {
                notification.onAction?.call();
                Navigator.pop(context);
              },
              child: Text(notification.actionLabel!),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Notification types
enum NotificationType {
  info,
  success,
  warning,
  error,
  anomaly,
  prediction,
  recommendation;

  IconData get icon {
    switch (this) {
      case NotificationType.info:
        return Icons.info;
      case NotificationType.success:
        return Icons.check_circle;
      case NotificationType.warning:
        return Icons.warning;
      case NotificationType.error:
        return Icons.error;
      case NotificationType.anomaly:
        return Icons.warning_amber;
      case NotificationType.prediction:
        return Icons.lightbulb;
      case NotificationType.recommendation:
        return Icons.tips_and_updates;
    }
  }

  Color get color {
    switch (this) {
      case NotificationType.info:
        return Colors.blue;
      case NotificationType.success:
        return Colors.green;
      case NotificationType.warning:
        return Colors.orange;
      case NotificationType.error:
        return Colors.red;
      case NotificationType.anomaly:
        return Colors.red;
      case NotificationType.prediction:
        return Colors.amber;
      case NotificationType.recommendation:
        return Colors.green;
    }
  }
}

/// App notification model
class AppNotification {
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  final bool isRead;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;
  final Map<String, dynamic>? data;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    DateTime? timestamp,
    this.isRead = false,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.data,
  }) : timestamp = timestamp ?? DateTime.now();

  AppNotification copyWith({
    String? id,
    String? title,
    String? message,
    NotificationType? type,
    DateTime? timestamp,
    bool? isRead,
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? onDismiss,
    Map<String, dynamic>? data,
  }) {
    return AppNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      actionLabel: actionLabel ?? this.actionLabel,
      onAction: onAction ?? this.onAction,
      onDismiss: onDismiss ?? this.onDismiss,
      data: data ?? this.data,
    );
  }
}
