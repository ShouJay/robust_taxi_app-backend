#!/usr/bin/env python3
"""
模擬車機：連線 MQTT，發送 register + 週期 location_update。

用法:
  pip install paho-mqtt
  python tests/mqtt_device_sim.py taxi-AAB-1234-rooftop 5

環境變數:
  MQTT_HOST (預設 localhost)
  MQTT_PORT (預設 1883)
"""
import json
import os
import sys
import time

import paho.mqtt.client as mqtt

DEVICE_ID = sys.argv[1] if len(sys.argv) > 1 else "taxi-AAB-1234-rooftop"
INTERVAL = float(sys.argv[2]) if len(sys.argv) > 2 else 5.0
PREFIX = os.getenv("MQTT_TOPIC_PREFIX", "taxi")
HOST = os.getenv("MQTT_HOST", "localhost")
PORT = int(os.getenv("MQTT_PORT", "1883"))


def main():
    cmd_topic = f"{PREFIX}/{DEVICE_ID}/cmd"
    evt_topic = f"{PREFIX}/{DEVICE_ID}/evt"

    def on_connect(client, userdata, flags, rc):
        if rc == 0:
            print(f"connected, subscribe {cmd_topic}")
            client.subscribe(cmd_topic, qos=1)
            reg = json.dumps({"type": "register", "device_id": DEVICE_ID})
            client.publish(evt_topic, reg, qos=1)
        else:
            print("connect failed", rc)

    def on_message(client, userdata, msg):
        print("cmd:", msg.payload.decode("utf-8", errors="replace")[:500])

    c = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1)
    c.on_connect = on_connect
    c.on_message = on_message
    c.connect(HOST, PORT, 60)
    c.loop_start()

    time.sleep(1)
    lon, lat = 121.5654, 25.0330
    try:
        while True:
            body = json.dumps(
                {
                    "type": "location_update",
                    "device_id": DEVICE_ID,
                    "longitude": lon,
                    "latitude": lat,
                }
            )
            c.publish(evt_topic, body, qos=1)
            print("sent location_update")
            time.sleep(INTERVAL)
    except KeyboardInterrupt:
        pass
    finally:
        c.loop_stop()
        c.disconnect()


if __name__ == "__main__":
    main()
