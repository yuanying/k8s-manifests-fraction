#!/usr/bin/env python3
"""Print the apiVersion and kind that each etcd value was stored with.

Reads the output of `etcdctl get <prefix> --prefix -w json` on stdin and
prints one tab-separated line per key:

    <key> <encoding> <apiVersion> <kind>

encoding is `protobuf` (b"k8s\\x00" + runtime.Unknown), `json`, `encrypted`
(b"k8s:enc:"), or `other`. Only the TypeMeta is decoded. The values
themselves (Secrets included) are never printed.

Run it with `python3 -I`.
"""
import base64
import json
import sys


def varint(b, i):
    shift = n = 0
    while True:
        c = b[i]
        i += 1
        n |= (c & 0x7F) << shift
        shift += 7
        if c < 0x80:
            return n, i


def fields(b):
    """Yield (field number, bytes) for the length-delimited fields of a message."""
    i = 0
    while i < len(b):
        tag, i = varint(b, i)
        num, wire = tag >> 3, tag & 7
        if wire == 2:
            ln, i = varint(b, i)
            yield num, b[i:i + ln]
            i += ln
        elif wire == 0:
            _, i = varint(b, i)
        else:
            raise ValueError(f"unexpected wire type {wire}")


def typemeta(v):
    if v.startswith(b"k8s:enc:"):
        return "encrypted", "?", "?"
    if v.startswith(b"k8s\x00"):
        # runtime.Unknown { TypeMeta typeMeta = 1 { apiVersion = 1; kind = 2 }; raw = 2; ... }
        for num, b in fields(v[4:]):
            if num == 1:
                tm = dict(fields(b))
                return "protobuf", tm.get(1, b"").decode(), tm.get(2, b"").decode()
        return "protobuf", "?", "?"
    try:
        o = json.loads(v)
        return "json", o.get("apiVersion", "?"), o.get("kind", "?")
    except ValueError:
        return "other", "?", "?"


def main():
    for kv in json.load(sys.stdin).get("kvs", []):
        key = base64.b64decode(kv["key"]).decode()
        enc, api_version, kind = typemeta(base64.b64decode(kv["value"]))
        print(f"{key}\t{enc}\t{api_version}\t{kind}")


if __name__ == "__main__":
    main()
