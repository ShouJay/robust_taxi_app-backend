import logging
from datetime import datetime

logger = logging.getLogger(__name__)

class EmergencyManager:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(EmergencyManager, cls).__new__(cls)
            cls._instance.initialize()
        return cls._instance

    def initialize(self):
        self.is_alarm_active = False
        self.marquee_text = "地震速報：請保持冷靜，尋找掩護。"
        # 預設警報影片檔名，App 應預先下載此影片以達成秒級切換
        self.emergency_video_filename = "earthquake_alert.mp4" 
        self.qr_scan_count = 0
        self.mqtt_bridge = None
        self._online_device_ids = None  # callable -> list[str]，由 app 注入
        logger.info("EmergencyManager initialized")

    def set_mqtt_bridge(self, mqtt_bridge, online_device_ids_callable=None):
        self.mqtt_bridge = mqtt_bridge
        self._online_device_ids = online_device_ids_callable

    def set_socketio(self, socketio):
        """向後相容佔位（已改 MQTT）。"""
        pass

    def trigger_alarm(self):
        if not self.is_alarm_active:
            self.is_alarm_active = True
            self.broadcast_state()
            logger.info("🚨 ALARM TRIGGERED 🚨")
            return True
        return False

    def reset_alarm(self):
        if self.is_alarm_active:
            self.is_alarm_active = False
            self.broadcast_state()
            logger.info(" ALARM RESET (Back to Normal)")
            return True
        return False

    def set_marquee(self, text):
        self.marquee_text = text
        # If we are in alarm mode (or if marquee is always shown), broadcast update
        self.broadcast_state()

    def set_emergency_video(self, filename):
        self.emergency_video_filename = filename
        self.broadcast_state()
        logger.info(f"Emergency video updated to: {filename}")

    def increment_qr_count(self):
        self.qr_scan_count += 1
        self.broadcast_stats()
        return self.qr_scan_count

    def get_state(self):
        return {
            "is_alarm_active": self.is_alarm_active,
            "marquee_text": self.marquee_text,
            "emergency_video": self.emergency_video_filename,
            "timestamp": datetime.now().isoformat()
        }

    def _broadcast_cmd_all(self, event_type, payload):
        if not self.mqtt_bridge:
            return
        ids = []
        if self._online_device_ids:
            try:
                ids = list(self._online_device_ids()) or []
            except Exception:
                ids = []
        for device_id in ids:
            self.mqtt_bridge.publish_cmd(device_id, event_type, payload)

    def broadcast_state(self):
        state = self.get_state()
        self._broadcast_cmd_all('system_state_update', state)

    def broadcast_stats(self):
        self._broadcast_cmd_all('stats_update', {
            "qr_scan_count": self.qr_scan_count,
            "timestamp": datetime.now().isoformat()
        })
