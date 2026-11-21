import argparse
import collections
import http.client
import statistics
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime


def parse_args():
    parser = argparse.ArgumentParser(description="Send requests from parallel workers for a fixed time and report throughput, errors and latency.")
    parser.add_argument("--url", required=True, help="base URL of the app, for example <app_url>")
    parser.add_argument("--path", default="/work?ms=200", help="path to request (default: /work?ms=200)")
    parser.add_argument("--concurrency", type=int, default=16, help="parallel workers (default: 16)")
    parser.add_argument("--duration", type=float, default=600, help="test length in seconds (default: 600)")
    parser.add_argument("--report", type=float, default=30, help="seconds between progress lines (default: 30)")
    parser.add_argument("--timeout", type=float, default=10, help="request timeout in seconds (default: 10)")
    return parser.parse_args()


def send(url, timeout):
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            response.read()
            outcome = str(response.status)
    except urllib.error.HTTPError as error:
        outcome = str(error.code)
    except (OSError, http.client.HTTPException) as error:
        reason = getattr(error, "reason", error)
        outcome = reason if isinstance(reason, str) else type(reason).__name__
    return outcome, (time.perf_counter() - started) * 1000


def work(url, timeout, deadline, stop, results, lock):
    while not stop.is_set() and time.monotonic() < deadline:
        result = send(url, timeout)
        with lock:
            results.append(result)


def describe(batch, seconds):
    latencies = sorted(ms for outcome, ms in batch if outcome == "200")
    errors = collections.Counter(outcome for outcome, _ in batch if outcome != "200")
    rate = len(batch) / seconds if seconds > 0 else 0
    text = f"{len(batch)} requests, {rate:.1f}/s, errors {sum(errors.values())}"
    if errors:
        text += f" {dict(errors)}"
    if latencies:
        p95 = statistics.quantiles(latencies, n=20)[18] if len(latencies) > 1 else latencies[0]
        text += f", p50 {statistics.median(latencies):.0f} ms, p95 {p95:.0f} ms"
    return text


def main():
    args = parse_args()
    url = args.url.rstrip("/") + args.path
    started_at = datetime.now().astimezone().isoformat(timespec="seconds")
    print(f"load test {args.path}, {args.concurrency} workers, {args.duration:g} s, started {started_at}", flush=True)
    results, lock, stop = [], threading.Lock(), threading.Event()
    started = time.monotonic()
    deadline = started + args.duration
    workers = [
        threading.Thread(target=work, args=(url, args.timeout, deadline, stop, results, lock), daemon=True)
        for _ in range(args.concurrency)
    ]
    for worker in workers:
        worker.start()
    cursor, window_start, next_report = 0, started, started + args.report
    try:
        while any(worker.is_alive() for worker in workers):
            time.sleep(0.2)
            now = time.monotonic()
            if now >= next_report:
                with lock:
                    batch, cursor = results[cursor:], len(results)
                print(f"{datetime.now():%H:%M:%S}  +{now - started:.0f}s  {describe(batch, now - window_start)}", flush=True)
                window_start, next_report = now, next_report + args.report
    except KeyboardInterrupt:
        stop.set()
        print("interrupted, waiting for requests in flight", flush=True)
        for worker in workers:
            worker.join(args.timeout)
    with lock:
        everything = list(results)
    print(f"\ntotal: {describe(everything, time.monotonic() - started)}")


if __name__ == "__main__":
    main()
