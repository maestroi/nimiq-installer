#!/usr/bin/env python3 

import os
import requests
import json
import time
import argparse
import logging

NIMIQ_NODE_URL = 'http://127.0.0.1:8648'
EXTERNAL_API_URL = 'https://blockmatrix.acestaking.com/blockheight/nimiq/testnet'
FACUET_URL = 'https://faucet.pos.nimiq-testnet.com/tapit'

logging.basicConfig(level=logging.INFO,
                    format='%(asctime)s — %(message)s',
                    datefmt='%Y-%m-%d_%H:%M:%S',
                    handlers=[logging.StreamHandler()])

def nimiq_request(method, params=None):
    response = requests.post(NIMIQ_NODE_URL, json={
        "jsonrpc": "2.0",
        "id": 1,
        "method": method,
        "params": params or [],
    })
    if response.status_code != 200:
        logging.error(f"Error: {response.status_code}")
        return None
    result = response.json().get('result', {})
    if result is None:
        logging.error(f"Error: {response.text}")
        return None
    return result

def get_private_key(file_path):
    with open(file_path, 'r') as f:
        lines = f.readlines()
        for line in lines:
            if 'Private Key:' in line:
                return line.split('Private Key:')[1].strip()
    return None

def needs_funds(address):
    res = nimiq_request("getAccountByAddress", [address])
    if res is None:
        return False
    data = res.get('data', {})
    if data is None or data.get('balance', 0) == 0:
        return True
    else:
        return False

def activate_validator():
    # Get address data
    private_key_location="/opt/nimiq/secrets/address.txt"
    res = nimiq_request("getAddress")
    ADDRESS = res['data']
    logging.info("Address: %s", ADDRESS)

    res = nimiq_request("getSigningKey")
    SIGKEY = res['data']
    logging.info("Signing Key: %s", SIGKEY)

    res = nimiq_request("getVotingKey")
    VOTEKEY = res['data']
    logging.info("Voting Key: %s", VOTEKEY)

    logging.info("Funding Nimiq address.")
    if needs_funds(ADDRESS):
        requests.post(FACUET_URL, data={'address': ADDRESS})
    else:
        logging.info("Address already funded.")

    ADDRESS_PRIVATE = get_private_key(private_key_location)
    logging.info("Importing private key.")
    nimiq_request("importRawKey", [ADDRESS_PRIVATE])

    logging.info("Unlock Account.")
    nimiq_request("unlockAccount", [ADDRESS])

    logging.info("Activate Validator")
    nimiq_request("sendNewValidatorTransaction", [ADDRESS, ADDRESS, SIGKEY, VOTEKEY, ADDRESS, "", "0"])

def check_block_height():
    logging.info("Waiting for consensus to be established.")
    while True:
        res = nimiq_request("isConsensusEstablished")
        if res['data'] == True:
            logging.info("Consensus established.")
            break
        else:
            time.sleep(5)

if __name__ == '__main__':
    logging.info(40 * '-')
    logging.info('Nimiq validator activation script')
    logging.info(40 * '-')
    check_block_height()
    activate_validator()
