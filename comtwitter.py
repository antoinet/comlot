#!/usr/bin/env python

import sys
import twitter

with open('/root/.twitter-keys', 'r') as f:
    keys = [line.strip() for line in f.readlines()]

api = twitter.Api(consumer_key=keys[0], consumer_secret=keys[1],
       access_token_key=keys[2], access_token_secret=keys[3])

print(api.VerifyCredentials())
status = api.PostUpdate('I love python-twitter!')
print(status)
