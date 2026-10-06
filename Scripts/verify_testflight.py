#!/usr/bin/env python3
"""Poll App Store Connect for the exact uploaded Dial Shot build.

A successful xcodebuild upload is not a processed TestFlight build. This
script fails unless ASC reports VALID or COMPLETE for the current run number.
Only the build ID/state are logged; the private key and token never are.
"""
import argparse
import json
import time
import urllib.parse
import urllib.request


def request_json(path: str, token: str) -> dict:
    request = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        headers={"Authorization": "Bearer " + token},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def find_build(app_id: str, build_number: str, token: str, request=request_json):
    query = urllib.parse.urlencode({"filter[app]": app_id, "sort": "-uploadedDate", "limit": "100"})
    builds = request("/v1/builds?" + query, token)["data"]
    return next((build for build in builds if build["attributes"].get("version") == build_number), None)


def await_build(bundle_id: str, build_number: str, token_factory, request=request_json,
                clock=time.monotonic, pause=time.sleep, timeout=900):
    query = urllib.parse.urlencode({"filter[bundleId]": bundle_id})
    apps = request("/v1/apps?" + query, token_factory())["data"]
    if len(apps) != 1:
        raise RuntimeError("Expected one App Store Connect app for the registered bundle ID")
    app_id = apps[0]["id"]
    print(f"App Store Connect app id: {app_id}", flush=True)
    deadline = clock() + timeout
    while clock() < deadline:
        build = find_build(app_id, build_number, token_factory(), request)
        if build is not None:
            state = build["attributes"].get("processingState")
            print(f"TestFlight build id={build['id']} build={build_number} state={state}", flush=True)
            if state in {"VALID", "COMPLETE"}:
                return build["id"]
            if state in {"INVALID", "FAILED"}:
                raise RuntimeError(f"TestFlight processing failed: {state}")
            if state != "PROCESSING":
                raise RuntimeError(f"Unexpected TestFlight processing state: {state}")
        pause(30)
    raise TimeoutError("Exact TestFlight build did not finish processing in 15 minutes")


def main():
    parser = argparse.ArgumentParser()
    for name in ("key", "key-id", "issuer-id", "bundle-id", "build"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    import jwt  # installed in an isolated venv by the macOS release job
    with open(args.key, encoding="utf-8") as handle:
        key = handle.read()

    def token():
        now = int(time.time())
        return jwt.encode({"iss": args.issuer_id, "aud": "appstoreconnect-v1",
                           "iat": now, "exp": now + 600}, key, algorithm="ES256",
                          headers={"kid": args.key_id})

    build_id = await_build(args.bundle_id, args.build, token)
    print(f"Processed TestFlight build id: {build_id}")


if __name__ == "__main__":
    main()
