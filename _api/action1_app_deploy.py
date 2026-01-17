#!/usr/bin/env python3
import os
import re
import sys
import json
import math
import time
import argparse
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

import requests
from dotenv import load_dotenv


REGION_BASE_URIS = {
    # From Action1's published PSAction1 module base URIs :contentReference[oaicite:7]{index=7}
    "NorthAmerica": "https://app.action1.com/api/3.0",
    "Europe": "https://app.eu.action1.com/api/3.0",
    "Australia": "https://app.au.action1.com/api/3.0",
}


@dataclass
class Action1Config:
    base_uri: str
    client_id: str
    client_secret: str
    chunk_bytes: int
    mac_platform_intel: str
    mac_platform_arm: str


class Action1Client:
    def __init__(self, cfg: Action1Config, timeout_s: int = 60):
        self.cfg = cfg
        self.timeout_s = timeout_s
        self._token: Optional[str] = None
        self._token_expiry_epoch: float = 0.0
        self._session = requests.Session()

    def _headers(self) -> Dict[str, str]:
        if not self._token:
            raise RuntimeError("Not authenticated")
        return {
            "Authorization": f"Bearer {self._token}",
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json",
        }

    def authenticate(self) -> None:
        # PSAction1 fetches token via POST {base}/oauth2/token with client_id/client_secret :contentReference[oaicite:8]{index=8}
        url = f"{self.cfg.base_uri}/oauth2/token"
        resp = self._session.post(
            url,
            data={"client_id": self.cfg.client_id, "client_secret": self.cfg.client_secret},
            timeout=self.timeout_s,
        )
        if resp.status_code >= 400:
            raise RuntimeError(f"Auth failed: {resp.status_code} {resp.text}")

        data = resp.json()
        self._token = data["access_token"]
        # expire a little early
        expires_in = int(data.get("expires_in", 300))
        self._token_expiry_epoch = time.time() + max(0, expires_in - 10)

    def ensure_auth(self) -> None:
        if not self._token or time.time() >= self._token_expiry_epoch:
            self.authenticate()

    def get(self, path: str, params: Optional[Dict[str, Any]] = None) -> Any:
        self.ensure_auth()
        url = f"{self.cfg.base_uri}{path}"
        resp = self._session.get(url, headers=self._headers(), params=params, timeout=self.timeout_s)
        if resp.status_code >= 400:
            raise RuntimeError(f"GET {path} failed: {resp.status_code} {resp.text}")
        return resp.json()

    def post(self, path: str, payload: Optional[Dict[str, Any]] = None, extra_headers: Optional[Dict[str, str]] = None) -> requests.Response:
        self.ensure_auth()
        url = f"{self.cfg.base_uri}{path}"
        headers = self._headers()
        if extra_headers:
            headers.update(extra_headers)
        resp = self._session.post(url, headers=headers, data=json.dumps(payload or {}), timeout=self.timeout_s)
        return resp

    def put_bytes(self, upload_url: str, body: bytes, headers: Dict[str, str]) -> requests.Response:
        self.ensure_auth()
        h = {"Authorization": f"Bearer {self._token}"}
        h.update(headers)
        return self._session.put(upload_url, headers=h, data=body, timeout=self.timeout_s)

    # ---- API operations ----

    def list_organizations(self) -> List[Dict[str, Any]]:
        # GET /organizations :contentReference[oaicite:9]{index=9}
        return self.get("/organizations")

    def list_packages(self) -> List[Dict[str, Any]]:
        # PSAction1 uses /packages/all?limit=9999 :contentReference[oaicite:10]{index=10}
        return self.get("/packages/all", params={"limit": 9999})

    def create_repo_package(self, org_id: str, name: str, vendor: str, description: str, scope: str) -> Dict[str, Any]:
        """
        Action1 apidocs define the exact payload schema for Software Repository Package POST.
        Here we send a minimal, readable structure; you can add fields your tenant requires.
        """
        payload = {
            "name": name,
            "vendor": vendor,
            "description": description,
            "scope": scope,
            "platform": "Mac",  # per UI you choose platform Windows/Mac :contentReference[oaicite:11]{index=11}
        }
        resp = self.post(f"/software-repository/{org_id}", payload)
        if resp.status_code >= 400:
            raise RuntimeError(f"Create repo package failed: {resp.status_code} {resp.text}")
        return resp.json()

    def create_version(self, org_id: str, package_id: str, version: str, meta: Dict[str, Any]) -> Dict[str, Any]:
        payload = {
            "version": version,
            # Many tenants store these on version objects; align to your apidocs field names if needed.
            **{k: v for k, v in meta.items() if v is not None and v != ""},
        }
        resp = self.post(f"/software-repository/{org_id}/{package_id}/versions", payload)
        if resp.status_code >= 400:
            raise RuntimeError(f"Create version failed: {resp.status_code} {resp.text}")
        return resp.json()

    def start_resumable_upload(self, package_id: str, version_id: str, platform: str, total_bytes: int) -> str:
        """
        Mirrors PSAction1 Start-Action1PackageUpload flow:
        POST /software-repository/all/{package}/versions/{version}/upload?platform=...
        with X-Upload-Content-Length and then read X-Upload-Location from response headers :contentReference[oaicite:12]{index=12}
        """
        path = f"/software-repository/all/{package_id}/versions/{version_id}/upload"
        resp = self.post(
            f"{path}?platform={platform}",
            payload={},
            extra_headers={
                "accept": "*/*",
                "X-Upload-Content-Type": "application/octet-stream",
                "X-Upload-Content-Length": str(total_bytes),
                "Content-Type": "application/json",
            },
        )
        # Action1 returns upload location in a header in this flow :contentReference[oaicite:13]{index=13}
        upload_loc = resp.headers.get("X-Upload-Location")
        if not upload_loc:
            raise RuntimeError(f"Upload init failed ({resp.status_code}): missing X-Upload-Location. Body: {resp.text}")
        return upload_loc

    def upload_file_in_chunks(self, upload_url: str, filename: str) -> None:
        chunk_size = self.cfg.chunk_bytes
        total = os.path.getsize(filename)
        sent = 0

        with open(filename, "rb") as f:
            while True:
                chunk = f.read(chunk_size)
                if not chunk:
                    break

                start = sent
                end = sent + len(chunk) - 1
                sent += len(chunk)

                headers = {
                    "Content-Type": "application/octet-stream",
                    "Content-Length": str(len(chunk)),
                    "Content-Range": f"bytes {start}-{end}/{total}",
                    "accept": "*/*",
                    "X-Upload-Content-Type": "application/octet-stream",
                }

                resp = self.put_bytes(upload_url, chunk, headers=headers)
                if resp.status_code >= 400 and resp.status_code not in (308,):  # 308 common for resumable
                    raise RuntimeError(f"Chunk upload failed: {resp.status_code} {resp.text}")

    def create_deploy_policy_instance(self, org_id: str, name: str, package_id: str, version_id: str) -> Dict[str, Any]:
        """
        PSAction1 uses /policies/instances/{orgId} and template_id deploy_package for software deploy automations :contentReference[oaicite:14]{index=14}
        The exact schema may vary; treat this as a starter and align with your apidocs.
        """
        payload = {
            "name": name,
            "retry_minutes": "1440",
            "endpoints": [{"id": "ALL", "type": "EndpointGroup"}],
            "actions": [
                {
                    "name": "Deploy Software",
                    "template_id": "deploy_package",
                    "params": {
                        "display_summary": "",
                        "packages": [
                            {
                                "id": package_id,
                                "version_id": version_id,
                            }
                        ],
                        "reboot_options": {"auto_reboot": "no"},
                    },
                }
            ],
        }
        resp = self.post(f"/policies/instances/{org_id}", payload)
        if resp.status_code >= 400:
            raise RuntimeError(f"Create deploy policy failed: {resp.status_code} {resp.text}")
        return resp.json()


def parse_app_zip_name(zip_path: str) -> Tuple[str, str]:
    base = os.path.basename(zip_path)
    m = re.match(r"^(?P<name>.+)-(?P<ver>[^-]+)\.zip$", base, re.IGNORECASE)
    if not m:
        raise ValueError("ZIP filename must look like APP-version.zip (e.g. Chrome-121.0.0.zip)")
    return m.group("name"), m.group("ver")


def prompt_optional(label: str) -> str:
    val = input(f"{label} (optional, Enter to skip): ").strip()
    return val


def choose_orgs(orgs: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    print("\nOrganizations:")
    for i, o in enumerate(orgs):
        print(f"  [{i}] {o.get('name','(no name)')}  ({o.get('id')})")

    raw = input("\nSelect org(s): comma list (e.g. 0,2) or 'all' for entire enterprise: ").strip().lower()
    if raw == "all":
        return orgs

    idxs = []
    for part in raw.split(","):
        part = part.strip()
        if part == "":
            continue
        idxs.append(int(part))

    selected = []
    for ix in idxs:
        if ix < 0 or ix >= len(orgs):
            raise ValueError(f"Invalid selection index: {ix}")
        selected.append(orgs[ix])
    return selected


def main() -> int:
    load_dotenv()

    parser = argparse.ArgumentParser(description="Action1 macOS app upload + optional deployment")
    parser.add_argument("--zip", dest="zip_path", required=True, help="Path to APP-version.zip")
    parser.add_argument("--region", dest="region", default=os.getenv("ACTION1_REGION", "Europe"),
                        choices=list(REGION_BASE_URIS.keys()))
    parser.add_argument("--deploy", action="store_true", help="Also create a Deploy Software policy instance")
    args = parser.parse_args()

    client_id = os.getenv("CLIENT_ID", "").strip()
    client_secret = os.getenv("CLIENT_SECRET", "").strip()
    if not client_id or not client_secret:
        print("Missing CLIENT_ID or CLIENT_SECRET in .env", file=sys.stderr)
        return 2

    chunk_mb = int(os.getenv("UPLOAD_CHUNK_MB", "24"))
    mac_platform_intel = os.getenv("MAC_PLATFORM_INTEL", "Mac_Intel")
    mac_platform_arm = os.getenv("MAC_PLATFORM_ARM", "Mac_AppleSilicon")

    cfg = Action1Config(
        base_uri=REGION_BASE_URIS[args.region],
        client_id=client_id,
        client_secret=client_secret,
        chunk_bytes=chunk_mb * 1024 * 1024,
        mac_platform_intel=mac_platform_intel,
        mac_platform_arm=mac_platform_arm,
    )
    a1 = Action1Client(cfg)

    if not os.path.isfile(args.zip_path):
        print(f"ZIP not found: {args.zip_path}", file=sys.stderr)
        return 2

    app_name, app_ver = parse_app_zip_name(args.zip_path)
    print(f"\nDetected from filename:\n  App: {app_name}\n  Version: {app_ver}")

    # Optional version metadata
    release_date = prompt_optional("Release date (YYYY-MM-DD)")
    notes = prompt_optional("Notes")
    update_type = prompt_optional("Update type (e.g. Regular Updates / Security Update)")
    cve = prompt_optional("CVE (e.g. CVE-2025-12345)")

    # Auth + org selection
    a1.authenticate()
    orgs = a1.list_organizations()
    selected_orgs = choose_orgs(orgs)

    # Package existence: we’ll search by name across packages and then still create versions per org
    all_packages = a1.list_packages()

    # crude match: exact name (case-insensitive)
    pkg_match = next((p for p in all_packages if str(p.get("name", "")).lower() == app_name.lower()), None)

    for org in selected_orgs:
        org_id = org.get("id")
        org_name = org.get("name", org_id)
        print(f"\n=== Org: {org_name} ({org_id}) ===")

        package_id = None

        if pkg_match:
            package_id = pkg_match.get("id")
            print(f"Found existing package by name: {app_name} (id={package_id})")
        else:
            print(f"No existing package named '{app_name}' found. Creating new Software Repository package…")
            name = input(f"Package Name [{app_name}]: ").strip() or app_name
            vendor = input("Vendor: ").strip()
            description = input("Description: ").strip()
            scope = input("Scope (IMPORTANT: cannot be changed later): ").strip()  # :contentReference[oaicite:15]{index=15}

            created = a1.create_repo_package(org_id, name, vendor, description, scope)
            package_id = created.get("id") or created.get("package_id")
            if not package_id:
                raise RuntimeError(f"Create package returned no id: {created}")
            print(f"Created package id={package_id}")

        # Create version
        meta = {
            "release_date": release_date,
            "notes": notes,
            "update_type": update_type,
            "cve": cve,
        }
        created_ver = a1.create_version(org_id, package_id, app_ver, meta)
        version_id = created_ver.get("id") or created_ver.get("version_id")
        if not version_id:
            raise RuntimeError(f"Create version returned no id: {created_ver}")
        print(f"Created version id={version_id}")

        # Upload ZIP (Intel + ARM)
        total_bytes = os.path.getsize(args.zip_path)
        print(f"Uploading ZIP ({math.ceil(total_bytes / (1024*1024))} MB)…")

        # Intel
        print(f" - Uploading for platform={cfg.mac_platform_intel}")
        upload_url = a1.start_resumable_upload(package_id, version_id, cfg.mac_platform_intel, total_bytes)
        a1.upload_file_in_chunks(upload_url, args.zip_path)

        # Apple Silicon
        print(f" - Uploading for platform={cfg.mac_platform_arm}")
        upload_url = a1.start_resumable_upload(package_id, version_id, cfg.mac_platform_arm, total_bytes)
        a1.upload_file_in_chunks(upload_url, args.zip_path)

        print("Upload complete.")

        if args.deploy:
            pol_name = f"Deploy {app_name} {app_ver}"
            created_pol = a1.create_deploy_policy_instance(org_id, pol_name, package_id, version_id)
            print(f"Created deployment policy: {created_pol.get('id', '(no id in response)')}")

    print("\nDone.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
