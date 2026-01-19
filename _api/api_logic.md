# Action1 Software Repository API Call Flow

## 1. POST /oauth2/token

Authenticate and obtain bearer token.

> **Why first:** All subsequent calls require `Authorization: Bearer <token>`

## 2. GET /organizations

List available organizations.

> **Why second:** Returns `orgId` required for all repository operations

## 3. GET /software-repository/{orgId}?custom=yes&builtin=no

List existing custom repositories.

> **Why before create:** Allows selection of existing repo, avoids duplicates

## 4. POST /software-repository/{orgId} *(optional)*

Create new repository if needed.

> **Why conditional:** Only if no suitable existing repo

## 5. GET /software-repository/{orgId}/{packageId}/versions *(optional)*

List existing versions for cloning.

> **Why before version create:** Enables cloning settings from previous versions

## 6. POST /software-repository/{orgId}/{packageId}/versions

Create new version with deployment settings.

> **Why after repo:** Requires `packageId` from step 3 or 4

## 7. POST /software-repository/{orgId}/{packageId}/versions/{versionId}/match-conflicts

Check for version conflicts.

> **Why after version:** Requires `versionId`, warns but doesn't block

## 8. POST /software-repository/{orgId}/{packageId}/versions/{versionId}/upload?platform={platform}

Initialize resumable upload, returns upload URL in `X-Upload-Location` header.

> **Why after version:** Associates file with specific version

## 9. PUT {upload_url}

Upload file in chunks using `Content-Range` header.

> **Why last:** Final step after all metadata is configured

## Dependency Chain

```text
token → orgId → packageId → versionId → upload_url
```
