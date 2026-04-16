"""
MQTT 橋接：訂閱 taxi/<device_id>/evt，發佈 taxi/<device_id>/cmd。
payload 格式：{"type": "<事件名>", ...}，與原 Socket.IO 事件名對齊。
"""

from __future__ import annotations

import json
import logging
import threading
from typing import Any, Callable, Optional

import paho.mqtt.client as mqtt

logger = logging.getLogger(__name__)


class MqttBridge:
    """後端 MQTT 客戶端：單例式使用，與 Flask 同進程。"""

    def __init__(
        self,
        host: str,
        port: int,
        username: str,
        password: str,
        topic_prefix: str,
        client_id: str,
        on_event: Callable[[str, dict], None],
    ):
        self._host = host
        self._port = port
        self._topic_prefix = topic_prefix.strip("/")
        self._on_event = on_event
        self._lock = threading.Lock()
        self._client = mqtt.Client(
            mqtt.CallbackAPIVersion.VERSION1,
            client_id=client_id,
            protocol=mqtt.MQTTv311,
        )
        if username:
            self._client.username_pw_set(username, password or "")
        self._client.on_connect = self._on_connect
        self._client.on_message = self._on_message
        self._client.on_disconnect = self._on_disconnect

    @property
    def topic_prefix(self) -> str:
        return self._topic_prefix

    def _evt_subscription_pattern(self) -> str:
        return f"{self._topic_prefix}/+/evt"

    def _parse_device_id(self, topic: str) -> Optional[str]:
        # taxi/<device_id>/evt
        parts = topic.split("/")
        if len(parts) >= 3 and parts[-1] == "evt":
            return parts[-2]
        return None

    def _on_connect(self, client, userdata, flags, rc):  # noqa: ANN001
        if rc == 0:
            pattern = self._evt_subscription_pattern()
            client.subscribe(pattern, qos=1)
            logger.info("MQTT 已連線並訂閱 %s", pattern)
        else:
            logger.error("MQTT 連線失敗 rc=%s", rc)

    def _on_disconnect(self, client, userdata, rc):  # noqa: ANN001
        logger.warning("MQTT 斷線 rc=%s", rc)

    def _on_message(self, client, userdata, msg):  # noqa: ANN001
        try:
            device_id = self._parse_device_id(msg.topic)
            if not device_id:
                logger.warning("無法解析 device_id: topic=%s", msg.topic)
                return
            payload = json.loads(msg.payload.decode("utf-8"))
            if not isinstance(payload, dict):
                logger.warning("evt 非 JSON object: %s", device_id)
                return
            with self._lock:
                self._on_event(device_id, payload)
        except json.JSONDecodeError as e:
            logger.error("MQTT payload JSON 解析失敗: %s", e)
        except Exception as e:
            logger.exception("MQTT 訊息處理錯誤: %s", e)

    def start(self) -> None:
        self._client.connect_async(self._host, self._port, keepalive=60)
        self._client.loop_start()
        logger.info("MQTT loop 已啟動 broker=%s:%s", self._host, self._port)

    def stop(self) -> None:
        try:
            self._client.loop_stop()
            self._client.disconnect()
        except Exception as e:
            logger.warning("MQTT stop: %s", e)

    def publish_cmd(self, device_id: str, event_type: str, payload: Optional[dict[str, Any]] = None) -> bool:
        """發佈一則指令到裝置 cmd topic。"""
        body: dict[str, Any] = {"type": event_type}
        if payload:
            for k, v in payload.items():
                if k != "type":
                    body[k] = v
        topic = f"{self._topic_prefix}/{device_id}/cmd"
        data = json.dumps(body, ensure_ascii=False)
        try:
            self._client.publish(topic, data, qos=1)
            return True
        except Exception as e:
            logger.error("MQTT publish 例外 device=%s: %s", device_id, e)
            return False

    def broadcast_cmd(self, device_ids: list[str], event_type: str, payload: Optional[dict[str, Any]] = None) -> None:
        for did in device_ids:
            self.publish_cmd(did, event_type, payload)
