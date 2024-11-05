import urllib.request
import json
import time
import gzip
import os
import sys
from datetime import datetime, timezone

headers = {'User-Agent': 'Go-http-client/2.0'} # the majority of traffic has this user agent


def printStderr(msg):
    print(msg, file=sys.stderr)

def lambda_handler(event, context):
    # fetch the JSON file
    url = 'https://toolbox-data.anchore.io/grype/databases/listing.json'
    printStderr(f"Fetching {url}")

    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request) as response:
        data = json.load(response)

    # find the latest v5 entry
    latest_v5 = next(
        entry for entry in data['available'].get("5", [])
    )
    db_url = latest_v5['url']

    printStderr(f"Downloading {db_url}")

    # download the database file and measure bytes per second
    download_stats = []
    total_bytes = 0
    start_time = time.time()
    last_log_time = start_time
    bytes_this_second = 0

    # set up request and read the response in chunks
    db_request = urllib.request.Request(db_url, headers=headers)
    with urllib.request.urlopen(db_request) as response:
        chunk_size = 1024  # 1 KB
        while True:
            # throw away the data, just measure the download speed
            chunk = response.read(chunk_size)
            if not chunk:
                break

            # update download counters
            total_bytes += len(chunk)
            bytes_this_second += len(chunk)
            current_time = time.time()

            # log per-second bytes
            if current_time - last_log_time >= 1:
                download_stats.append(bytes_this_second)
                show(bytes_this_second)
                bytes_this_second = 0
                last_log_time = current_time

    end_time = time.time()
    total_time = end_time - start_time
    avg_bps = total_bytes / total_time if total_time > 0 else 0
    avg_mbps = avg_bps / 1024 / 1024

    printStderr(f"Downloaded {total_bytes} bytes in {total_time} seconds ({avg_mbps} MB/s)")

    # return download stats
    local_time = datetime.fromtimestamp(start_time)
    utc_time = local_time.astimezone(timezone.utc)
    stats = {
        "start": utc_time.isoformat(),
        "in-aws": "yes" if os.environ.get("AWS_EXECUTION_ENV") else "no",
        "region": os.environ.get("AWS_REGION", "unknown"),
        "total_bytes": total_bytes,
        "total_time": total_time,
        "average_bps": avg_bps,
        "average_mbps": avg_mbps,
        "bps_log": download_stats,
        "db_url": db_url
    }
    return stats

def show(bytes_this_second, max_length=100):
    bps = bytes_this_second
    bar_length = bps // 1024 // 1024  # scale to MB for better readability
    bar = "#" * min(bar_length, max_length)  # limit max bar length to 50 chars
    if len(bar) == max_length:
        bar += "..."
    printStderr(f"{bps:>7} B/s ({bar_length} MB) | {bar}")

if __name__ == '__main__':
    print(json.dumps(lambda_handler(None, None), indent=4))
