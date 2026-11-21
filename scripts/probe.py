import argparse
import collections
import http.client
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime


def parse_args():
    parser = argparse.ArgumentParser(description="Poll a URL at a fixed interval and print one line per request.")
    parser.add_argument("--url", required=True, help="URL to poll, for example <app_url>/api/info")
    parser.add_argument("--interval", type=float, default=1.0, help="seconds between requests (default: 1)")
    parser.add_argument("--count", type=int, default=0, help="stop after this many requests (default: run until Ctrl+C)")
    parser.add_argument("--timeout", type=float, default=2.0, help="request timeout in seconds (default: 2)")
    return parser.parse_args()


def fetch(url, timeout):
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            status, body = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, body = error.code, b""
    except (OSError, http.client.HTTPException) as error:
        reason = getattr(error, "reason", error)
        return reason if isinstance(reason, str) else type(reason).__name__, {}, elapsed_ms(started)
    try:
        data = json.loads(body)
    except ValueError:
        data = {}
    return status, data if isinstance(data, dict) else {}, elapsed_ms(started)


def elapsed_ms(started):
    return (time.perf_counter() - started) * 1000


def print_summary(sent, errors, seen, zones):
    print(f"\nrequests {sent}, ok {sent - len(errors)}, errors {len(errors)}")
    if errors:
        kinds = collections.Counter(kind for _, kind in errors)
        print(f"errors by kind {dict(kinds)}, first at {errors[0][0]}, last at {errors[-1][0]}")
    for kind in ("instance", "version"):
        for value, (first, last, count) in seen[kind].items():
            where = f" ({zones[value]})" if kind == "instance" else ""
            print(f"{kind} {value}{where}: {count} responses, {first} - {last}")


def main():
    args = parse_args()
    path = urllib.parse.urlsplit(args.url).path or "/"
    started_at = datetime.now().astimezone().isoformat(timespec="seconds")
    print(f"probe {path} every {args.interval:g} s, started {started_at}", flush=True)
    sent, errors, zones = 0, [], {}
    seen = {"instance": {}, "version": {}}
    next_at = time.monotonic()
    try:
        while not args.count or sent < args.count:
            delay = next_at - time.monotonic()
            if delay > 0:
                time.sleep(delay)
            next_at += args.interval
            stamp = datetime.now().strftime("%H:%M:%S")
            status, data, ms = fetch(args.url, args.timeout)
            sent += 1
            if status != 200:
                errors.append((stamp, str(status)))
                print(f"{stamp}  ERR  {status}  {ms:.0f} ms", flush=True)
                continue
            instance = data.get("instance_id", "-")
            zone = data.get("zone", "-")
            version = data.get("version", "-")
            print(f"{stamp}  200  {instance}  {zone}  {version}  visits={data.get('visits', '-')}  {ms:.0f} ms", flush=True)
            zones[instance] = zone
            for kind, value in (("instance", instance), ("version", version)):
                first, _, count = seen[kind].get(value, (stamp, stamp, 0))
                seen[kind][value] = (first, stamp, count + 1)
    except KeyboardInterrupt:
        pass
    print_summary(sent, errors, seen, zones)


if __name__ == "__main__":
    main()
