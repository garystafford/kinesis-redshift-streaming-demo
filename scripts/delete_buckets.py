#!/usr/bin/env python3

# Delete buckets
# Author: Gary A. Stafford (February 2020)

import boto3
import os

DATA_BUCKET = os.environ.get('DATA_BUCKET')
LOG_BUCKET = os.environ.get('LOG_BUCKET')

s3 = boto3.resource('s3')
bucket = s3.Bucket(DATA_BUCKET)
bucket.object_versions.delete()

bucket = s3.Bucket(LOG_BUCKET)
bucket.object_versions.delete()

bucket.delete()
