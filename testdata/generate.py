#!/usr/bin/env -S uv run --script --managed-python
# /// script
# requires-python = ">=3.12"
# dependencies = ["cryptography"]
# ///
"""regenerates vectors.json from fixed inputs, independently of the swift and kotlin code"""

import hashlib
import json
from pathlib import Path

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

SALT = b"notifbridge/1"

PHONE_STATIC_PRIVATE = "8bf52fdf679746bed5c360faabade18348c82763802bf96e6e0c4559470b1ec7"
PHONE_EPHEMERAL_PRIVATE = "6d264925ad9f66f87b2ec6c562c3abeea2f3547fa35022402e6f03cb40a9415f"
MAC_STATIC_PRIVATE = "dcd4172e0b5e0b5ffbe0d3b00fcbae17051de314742b9930e7d3f5dc961d2d90"
NONCE = "000102030405060708090a0b"
MESSAGE = {
    "type": "posted",
    "key": "0|com.example|1|null|10001",
    "package": "com.example",
    "appName": "Example",
    "title": "Hello",
    "text": "World",
    "ts": 1761177600000,
}


def key_pair(private_hex: str) -> tuple[X25519PrivateKey, bytes]:
    private = X25519PrivateKey.from_private_bytes(bytes.fromhex(private_hex))
    return private, private.public_key().public_bytes_raw()


def main() -> None:
    phone, phone_public = key_pair(PHONE_STATIC_PRIVATE)
    ephemeral, ephemeral_public = key_pair(PHONE_EPHEMERAL_PRIVATE)
    mac, mac_public = key_pair(MAC_STATIC_PRIVATE)

    ikm = phone.exchange(mac.public_key()) + ephemeral.exchange(mac.public_key())
    session_key = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=SALT,
        info=phone_public + ephemeral_public + mac_public,
    ).derive(ikm)

    plaintext = json.dumps(MESSAGE, separators=(",", ":"))
    nonce = bytes.fromhex(NONCE)
    sealed = nonce + AESGCM(session_key).encrypt(nonce, plaintext.encode(), None)

    vectors = {
        "macFingerprintSha256": hashlib.sha256(mac_public).hexdigest(),
        "macStaticPrivate": MAC_STATIC_PRIVATE,
        "macStaticPublic": mac_public.hex(),
        "nonce": NONCE,
        "phoneEphemeralPrivate": PHONE_EPHEMERAL_PRIVATE,
        "phoneEphemeralPublic": ephemeral_public.hex(),
        "phoneStaticPrivate": PHONE_STATIC_PRIVATE,
        "phoneStaticPublic": phone_public.hex(),
        "plaintext": plaintext,
        "sealed": sealed.hex(),
        "sessionKey": session_key.hex(),
    }
    output = json.dumps(vectors, indent=2, sort_keys=True, separators=(",", " : "))
    Path(__file__).with_name("vectors.json").write_text(output + "\n")


if __name__ == "__main__":
    main()
