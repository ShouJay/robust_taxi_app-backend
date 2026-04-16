"""
配置文件
存儲所有應用程序配置參數
"""

import os

# MongoDB 連接配置
MONGODB_URI = os.getenv('MONGODB_URI', 'mongodb+srv://taxi_user:taxi@taxidb.ed4tqft.mongodb.net/?appName=TaxiDB')
DATABASE_NAME = os.getenv('DATABASE_NAME', 'smart_taxi_ads')

# Flask 配置
# FLASK_HOST = os.getenv('FLASK_HOST', '0.0.0.0')
# FLASK_PORT = int(os.getenv('FLASK_PORT', 8080))
FLASK_HOST = '0.0.0.0'
FLASK_PORT = 8080
FLASK_DEBUG = os.getenv('FLASK_DEBUG', 'True').lower() == 'true'

# 業務配置
DEFAULT_VIDEO = os.getenv('DEFAULT_VIDEO', 'default_ad_loop.mp4')

# 日誌配置
LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')

# MQTT（與 Mosquitto / 其他 Broker 相容）
MQTT_HOST = os.getenv('MQTT_HOST', 'localhost')
MQTT_PORT = int(os.getenv('MQTT_PORT', '1883'))
MQTT_USER = os.getenv('MQTT_USER', '') or ''
MQTT_PASSWORD = os.getenv('MQTT_PASSWORD', '') or ''
MQTT_TOPIC_PREFIX = os.getenv('MQTT_TOPIC_PREFIX', 'taxi')
# 後端作為 client 的 client_id（可覆寫避免多實例衝突）
MQTT_CLIENT_ID = os.getenv('MQTT_CLIENT_ID', 'robust_taxi_backend')

