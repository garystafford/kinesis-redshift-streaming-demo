#!/usr/bin/env python3

# Simulated streaming time-series iot sensor data
# Author: Gary A. Stafford (February 2020)

import json
from datetime import datetime

import boto3

STREAM_NAME = 'redshift-delivery-stream'
client = boto3.client('firehose')


def create_data():
    payload = {
        'guid': 'test-guid-test-guid-test-guid',
        'ts': int(datetime.now().strftime('%s')),
        'temp': 999.99
    }
    return payload


def send_to_kinesis(payload):
    _ = client.put_record(
        DeliveryStreamName=STREAM_NAME,
        Record={
            'Data': json.dumps(payload)
        }
    )


def main():
    payload = create_data()
    print(json.dumps(payload))
    send_to_kinesis(payload)


if __name__ == '__main__':
    main()
