import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../config/app_config.dart';
import '../models/play_ad_command.dart';

/// MQTT 傳輸層（檔名保留為 websocket_manager 以降低改動面）
/// 對應後端 taxi/<deviceId>/cmd 與 taxi/<deviceId>/evt
class WebSocketManager {
  MqttServerClient? _client;
  String deviceId;
  final String mqttHost;
  final int mqttPort;
  final String topicPrefix;

  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  bool get isRegistered => isConnected && _isRegistered;

  bool _isRegistered = false;

  Function(PlayAdCommand)? onPlayAdCommand;
  Function(DownloadVideoCommand)? onDownloadVideoCommand;
  Function()? onConnected;
  Function()? onDisconnected;
  Function(String)? onRegistrationSuccess;
  Function(String)? onRegistrationError;
  Function(Map<String, dynamic>)? onLocationAck;
  Function(String, List<dynamic>)? onStartCampaignPlayback;
  Function()? onRevertToLocalPlaylist;

  Timer? _heartbeatTimer;
  Timer? _locationTimer;

  WebSocketManager({
    required this.deviceId,
    String? mqttHost,
    int? mqttPort,
    String? topicPrefix,
  }) : mqttHost = mqttHost ?? AppConfig.mqttBrokerHost,
       mqttPort = mqttPort ?? AppConfig.mqttBrokerPort,
       topicPrefix = topicPrefix ?? AppConfig.mqttTopicPrefix;

  String get _cmdTopic => '$topicPrefix/$deviceId/cmd';
  String get _evtTopic => '$topicPrefix/$deviceId/evt';

  void connect() {
    _isRegistered = false;
    _client?.disconnect();
    _client = MqttServerClient.withPort(
      mqttHost,
      'flutter_${deviceId}',
      mqttPort,
    );
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 30;
    _client!.autoReconnect = true;
    _client!.resubscribeOnAutoReconnect = true;
    _client!.onConnected = _onMqttConnected;
    _client!.onDisconnected = _onMqttDisconnected;
    _client!.onAutoReconnect = _onAutoReconnect;

    final conn = MqttConnectMessage()
        .withClientIdentifier('flutter_${deviceId}_${DateTime.now().millisecondsSinceEpoch}')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    _client!.connectionMessage = conn;

    try {
      _client!.connect();
    } catch (e) {
      print('❌ MQTT connect 失敗: $e');
      return;
    }

    _updatesSub?.cancel();
    _updatesSub = _client!.updates!.listen(_onMqttMessages);
  }

  void _onMqttConnected() {
    print('✅ MQTT 已連線');
    _client!.subscribe(_cmdTopic, MqttQos.atLeastOnce);
    _registerDevice();
    _startHeartbeat();
    onConnected?.call();
  }

  void _onMqttDisconnected() {
    print('❌ MQTT 已斷線');
    _isRegistered = false;
    _stopHeartbeat();
    _stopLocationUpdates();
    onDisconnected?.call();
  }

  void _onAutoReconnect() {
    print('🔄 MQTT 自動重連中…');
  }

  void _onMqttMessages(List<MqttReceivedMessage<MqttMessage?>>? c) {
    if (c == null) return;
    for (final rec in c) {
      final msg = rec.payload;
      if (msg is! MqttPublishMessage) continue;
      final payload = MqttPublishPayload.bytesToStringAsString(
        msg.payload.message,
      );
      if (payload.isEmpty) continue;
      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        _dispatchCmd(data);
      } catch (e) {
        print('❌ 解析 MQTT cmd 失敗: $e');
      }
    }
  }

  void _dispatchCmd(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null) return;

    switch (type) {
      case 'registration_success':
        _onRegistrationSuccess(data);
        break;
      case 'registration_error':
        _onRegistrationError(data);
        break;
      case 'play_ad':
        _onPlayAd(data);
        break;
      case 'location_ack':
        _onLocationAck(data);
        break;
      case 'heartbeat_ack':
        break;
      case 'download_video':
        _onDownloadVideo(data);
        break;
      case 'download_status_ack':
        break;
      case 'force_disconnect':
        _onForceDisconnect(data);
        break;
      case 'start_campaign_playback':
        _onStartCampaignPlayback(data);
        break;
      case 'revert_to_local_playlist':
        _onRevertToLocalPlaylist(data);
        break;
      case 'system_state_update':
      case 'stats_update':
      case 'qr_stats_update':
        break;
      case 'delete_local_video':
        onDeleteLocalVideoCommand?.call(
          data['video_filename'] as String? ?? '',
        );
        break;
      default:
        print('📡 未處理的 MQTT cmd type: $type');
    }
  }

  /// 刪除本機影片（後端指令）
  Function(String videoFilename)? onDeleteLocalVideoCommand;

  void _emitEvt(String type, Map<String, dynamic> payload) {
    if (!isConnected) {
      print('⚠️ 未連接，無法發送 $type');
      return;
    }
    final body = <String, dynamic>{'type': type, ...payload};
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(body));
    _client!.publishMessage(_evtTopic, MqttQos.atLeastOnce, builder.payload!);
  }

  void _registerDevice() {
    print('📝 註冊設備: $deviceId');
    _emitEvt('register', {'device_id': deviceId});
  }

  void sendLocationUpdate(double longitude, double latitude) {
    if (!isConnected) {
      print('⚠️ 未連接，無法發送位置');
      return;
    }
    if (longitude < -180 || longitude > 180) return;
    if (latitude < -90 || latitude > 90) return;

    _emitEvt('location_update', {
      'device_id': deviceId,
      'longitude': longitude,
      'latitude': latitude,
      'timestamp': DateTime.now().toIso8601String(),
    });
    print('📍 發送位置: ($latitude, $longitude)');
  }

  void sendHeartbeat() {
    if (!isConnected) return;
    _emitEvt('heartbeat', {'device_id': deviceId});
    print('💓 發送心跳');
  }

  void sendDownloadStatus({
    required String advertisementId,
    required String status,
    required int progress,
    required List<int> downloadedChunks,
    required int totalChunks,
    String? errorMessage,
  }) {
    if (!isConnected) return;
    _emitEvt('download_status', {
      'device_id': deviceId,
      'advertisement_id': advertisementId,
      'status': status,
      'progress': progress,
      'downloaded_chunks': downloadedChunks,
      'total_chunks': totalChunks,
      'error_message': errorMessage,
    });
    print('📊 發送下載狀態: $advertisementId - $status ($progress%)');
  }

  void sendDownloadRequest(String advertisementId) {
    if (!isConnected) return;
    _emitEvt('download_request', {
      'device_id': deviceId,
      'advertisement_id': advertisementId,
    });
    print('📥 請求下載: $advertisementId');
  }

  void _emitPlaybackEvent(String event, Map<String, dynamic> payload) {
    if (!isConnected) {
      print('⚠️ 未連接，無法發送 $event');
      return;
    }
    final data = {
      'device_id': deviceId,
      'event': event,
      'timestamp': DateTime.now().toIso8601String(),
      ...payload,
    };
    _emitEvt(event, data);
    print('📡 發送 $event');
  }

  void sendPlaybackStarted({
    required String mode,
    required String advertisementId,
    required String videoFilename,
    String? campaignId,
    String? trigger,
    int? playlistIndex,
    int? playlistLength,
  }) {
    final payload = <String, dynamic>{
      'mode': mode,
      'advertisement_id': advertisementId,
      'video_filename': videoFilename,
    };
    if (campaignId != null && campaignId.isNotEmpty) {
      payload['campaign_id'] = campaignId;
    }
    if (trigger != null && trigger.isNotEmpty) {
      payload['trigger'] = trigger;
    }
    if (playlistIndex != null) {
      payload['playlist_index'] = playlistIndex;
    }
    if (playlistLength != null) {
      payload['playlist_length'] = playlistLength;
    }
    _emitPlaybackEvent('playback_started', payload);
  }

  void sendPlaybackCompleted({
    required String mode,
    required String advertisementId,
    required String videoFilename,
    String? campaignId,
    String? trigger,
    int? playlistIndex,
    int? playlistLength,
    int? nextPlaylistIndex,
    Duration? playbackDuration,
  }) {
    final payload = <String, dynamic>{
      'mode': mode,
      'advertisement_id': advertisementId,
      'video_filename': videoFilename,
    };
    if (campaignId != null && campaignId.isNotEmpty) {
      payload['campaign_id'] = campaignId;
    }
    if (trigger != null && trigger.isNotEmpty) {
      payload['trigger'] = trigger;
    }
    if (playlistIndex != null) {
      payload['playlist_index'] = playlistIndex;
    }
    if (playlistLength != null) {
      payload['playlist_length'] = playlistLength;
    }
    if (nextPlaylistIndex != null) {
      payload['next_playlist_index'] = nextPlaylistIndex;
    }
    if (playbackDuration != null) {
      payload['playback_duration_ms'] = playbackDuration.inMilliseconds;
    }
    _emitPlaybackEvent('playback_completed', payload);
  }

  void sendPlaybackModeChange({
    required String mode,
    String? campaignId,
    String? reason,
    String? previousMode,
  }) {
    final payload = <String, dynamic>{'mode': mode};
    if (campaignId != null && campaignId.isNotEmpty) {
      payload['campaign_id'] = campaignId;
    }
    if (reason != null && reason.isNotEmpty) {
      payload['reason'] = reason;
    }
    if (previousMode != null && previousMode.isNotEmpty) {
      payload['previous_mode'] = previousMode;
    }
    _emitPlaybackEvent('playback_mode_change', payload);
  }

  /// 完整清單快照（供後台顯示）
  void sendPlaybackSnapshot(Map<String, dynamic> snapshot) {
    if (!isConnected) return;
    _emitEvt('playback_snapshot', snapshot);
  }

  void sendPlaybackError({
    required String error,
    required String videoFilename,
    String? campaignId,
    String? advertisementId,
    String mode = 'unknown',
    int? playlistIndex,
    int? playlistLength,
    String? trigger,
  }) {
    final payload = <String, dynamic>{
      'error': error,
      'video_filename': videoFilename,
      'mode': mode,
      'advertisement_id': advertisementId ?? 'unknown',
    };
    if (campaignId != null && campaignId.isNotEmpty) {
      payload['campaign_id'] = campaignId;
    }
    if (playlistIndex != null) {
      payload['playlist_index'] = playlistIndex;
    }
    if (playlistLength != null) {
      payload['playlist_length'] = playlistLength;
    }
    if (trigger != null && trigger.isNotEmpty) {
      payload['trigger'] = trigger;
    }
    _emitPlaybackEvent('playback_error', payload);
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(AppConfig.heartbeatInterval, (_) {
      sendHeartbeat();
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void startLocationUpdates(double longitude, double latitude) {
    _stopLocationUpdates();
    sendLocationUpdate(longitude, latitude);
    _locationTimer = Timer.periodic(AppConfig.locationUpdateInterval, (_) {
      sendLocationUpdate(longitude, latitude);
    });
  }

  void _stopLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  void _onRegistrationSuccess(dynamic data) {
    print('✅ 註冊成功: ${data['message']}');
    print('   設備類型: ${data['device_type']}');
    _isRegistered = true;
    onRegistrationSuccess?.call(data['message'] as String);
  }

  void _onRegistrationError(dynamic data) {
    print('❌ 註冊失敗: ${data['error']}');
    _isRegistered = false;
    onRegistrationError?.call(data['error'] as String);
  }

  void _onPlayAd(dynamic data) {
    print('🎬 收到播放廣告命令 (MQTT)');
    try {
      final command = PlayAdCommand.fromJson(data as Map<String, dynamic>);
      onPlayAdCommand?.call(command);
    } catch (e, stackTrace) {
      print('❌ 解析播放命令失敗: $e');
      print('錯誤堆疊: $stackTrace');
    }
  }

  void _onLocationAck(dynamic data) {
    print('✅ 位置更新確認: ${data['message']}');
    if (data['video_filename'] != null) {
      print('   推送影片: ${data['video_filename']}');
    }
    onLocationAck?.call(data as Map<String, dynamic>);
  }

  void _onDownloadVideo(dynamic data) {
    print('📥 收到下載命令');
    try {
      final command = DownloadVideoCommand.fromJson(
        data as Map<String, dynamic>,
      );
      onDownloadVideoCommand?.call(command);
    } catch (e) {
      print('❌ 解析下載命令失敗: $e');
    }
  }

  void _onForceDisconnect(dynamic data) {
    print('⚠️ 伺服器強制斷開: ${data['reason']}');
    disconnect();
  }

  void _onStartCampaignPlayback(dynamic data) {
    final campaignId = data is Map<String, dynamic>
        ? data['campaign_id'] as String? ?? ''
        : '';
    final playlist = data is Map<String, dynamic>
        ? (data['playlist'] as List<dynamic>? ?? [])
        : const [];

    if (campaignId.isEmpty) {
      print('⚠️ 收到活動播放命令但缺少 campaign_id: $data');
      return;
    }

    print('🎬 收到活動播放命令: $campaignId (項目: ${playlist.length})');
    onStartCampaignPlayback?.call(campaignId, playlist);
  }

  void _onRevertToLocalPlaylist(dynamic data) {
    print('🏠 收到切換回本地播放命令');
    onRevertToLocalPlaylist?.call();
  }

  void updateDeviceId(String newDeviceId) {
    deviceId = newDeviceId;
    if (isConnected) {
      _isRegistered = false;
      disconnect();
      Future.delayed(const Duration(seconds: 1), () {
        connect();
      });
    }
  }

  void disconnect() {
    _stopHeartbeat();
    _stopLocationUpdates();
    _updatesSub?.cancel();
    _updatesSub = null;
    _client?.disconnect();
    _client = null;
    _isRegistered = false;
    print('🔌 已斷開 MQTT');
  }

  void dispose() {
    disconnect();
  }
}
