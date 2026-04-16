/// 應用程式配置
class AppConfig {
  // 後端服務地址（請根據實際環境修改）
  static const String baseUrl = 'https://robusttaxi.azurewebsites.net';

  // 🔽🔽🔽 本地除錯時可改為電腦 IP + Docker（HTTP API）🔽🔽🔽
  // static const String baseUrl = 'http://192.168.0.249:8080';
  // 🔼🔼🔼

  /// MQTT Broker（與 docker-compose 內 Mosquitto 對齊；生產環境請改為實際主機）
  static const String mqttBrokerHost = '127.0.0.1';
  static const int mqttBrokerPort = 1883;
  static const String mqttTopicPrefix = 'taxi';

  // API 版本
  static const String apiVersion = 'v1';

  // API 端點
  static String get apiBaseUrl => '$baseUrl/api/$apiVersion';

  // WebSocket 配置
  static const Duration heartbeatInterval = Duration(seconds: 30);
  static const Duration locationUpdateInterval = Duration(seconds: 5);
  static const Duration reconnectDelay = Duration(seconds: 5);

  // 下載配置
  static const int defaultChunkSize = 10485760; // 10MB
  static const int maxConcurrentDownloads = 3;
  static const int downloadRetryAttempts = 3;

  // 本地儲存鍵值
  static const String deviceIdKey = 'device_id';
  static const String defaultDeviceId = 'taxi-AAB-1234-rooftop';
  static const String adminModeKey = 'admin_mode';

  // 播放配置
  static const int tapCountToSettings = 5;
  static const Duration tapDetectionWindow = Duration(seconds: 3);
}
