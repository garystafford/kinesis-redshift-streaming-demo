#!/usr/bin/env python3

# Simulated single IoT message to Kinesis
# Author: Gary A. Stafford
# Date: Revised October 2020

import json
import random
from datetime import datetime

import boto3
import time as tm
import numpy as np
import threading

STREAM_NAME = 'redshift-delivery-stream'

client = boto3.client('firehose')


class MyThread(threading.Thread):
    def __init__(self, thread_id, sensor_guid, temp_max):
        threading.Thread.__init__(self)
        self.thread_id = thread_id
        self.sensor_id = sensor_guid
        self.temp_max = temp_max

    def run(self):
        print("Starting Thread: " + str(self.thread_id))
        self.create_data()
        print("Exiting Thread: " + str(self.thread_id))

    def create_data(self):
        start = 0
        stop = 20
        step = 0.1  # step size (e.g 0 to 20, step .1 = 200 steps in cycle)
        repeat = 2  # how many times to repeat cycle
        freq = 60  # frequency of temperature reading in seconds
        max_range = int(stop * (1 / step))
        time = np.arange(start, stop, step)
        amplitude = np.sin(time)
        for x in range(0, repeat):
            for y in range(0, max_range):
                temperature = round((((amplitude[y] + 1.0) * self.temp_max) + random.uniform(-5, 5)) + 60, 2)
                payload = {
                    'guid': self.sensor_id,
                    'ts': int(datetime.now().strftime('%s')),
                    'temp': temperature
                }

                print(json.dumps(payload))

                self.send_to_kinesis(payload)

                tm.sleep(freq)

    @staticmethod
    def send_to_kinesis(payload):
        _ = client.put_record(
            DeliveryStreamName=STREAM_NAME,
            Record={
                'Data': json.dumps(payload)
            }
        )


def main():
    sensor_guids = [
        "03e39872-e105-4be4-83c0-9ade818465dc",
        "fa565921-fddd-4bfb-a7fd-d617f816df4b",
        "d120422d-5789-435d-9dc6-73d8489b04c2",
        "93238559-4d55-4b2a-bdcb-6aa3be0f3908",
        "dbc05806-6872-4f0a-aca2-f794cc39bd9b",
        "f9ade639-f936-4954-aa5a-1f2ed86c9bcf"
    ]
    timeout = 300  # arbitrarily offset the start of threads (60 / 5 = 12)

    # Create new threads
    thread1 = MyThread(1, sensor_guids[0], 25)
    thread2 = MyThread(2, sensor_guids[1], 10)
    thread3 = MyThread(3, sensor_guids[2], 7)
    thread4 = MyThread(4, sensor_guids[3], 30)
    thread5 = MyThread(5, sensor_guids[4], 5)
    thread6 = MyThread(6, sensor_guids[5], 12)

    # Start new threads
    thread1.start()
    tm.sleep(timeout * 1)
    thread2.start()
    tm.sleep(timeout * 2)
    thread3.start()
    tm.sleep(timeout * 1)
    thread4.start()
    tm.sleep(timeout * 3)
    thread5.start()
    tm.sleep(timeout * 2)
    thread6.start()

    # Wait for threads to terminate
    thread1.join()
    thread2.join()
    thread3.join()
    thread4.join()
    thread5.join()
    thread6.join()
    print("Exiting Main Thread")


if __name__ == '__main__':
    main()
