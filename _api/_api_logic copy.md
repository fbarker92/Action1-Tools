# POST /auth2/token 
- Get the auth bearer token for subsequent API calls

# GET /org
- Get a list of all current organistaions

# GET /software-repository/all?builtin=No&platform=Mac
- Get a list of all existing software repositories (for Mac and not builtin)
    - Display this as a list to the user so that an existing software repo can be used
    - Give the user the optoin to create a new software repo if needed

# POST /software-repository/{orgId}
- Create a new software repo if required
- request schema;
```bash
{
  "name": "<SoftwareRepoName>",
  "vendor": "<SoftwareVendor>",
  "description": "<SoftwareDescription>",
  "internal_notes": "<InternalNotes>",
  "platform": "<Mac | Windows | Linux>"
}
```
- response schema
```bash
{
  "id": "API_TEST_API_TEST_REPO_1768734965403",
  "type": "SoftwareRepositoryPackage",
  "self": "https://app.eu.action1.com/api/3.0/software-repository/all/API_TEST_API_TEST_REPO_1768734965403",
  "builtin": "no",
  "name": "API TEST REPO",
  "vendor": "API TEST",
  "description": "API TEST.",
  "status": "Published",
  "platform": "Mac",
  "internal_notes": "API sInternal notes about the package here.",
  "update_type": "App",
  "scope": {
    "type": "Enterprise"
  }
  scope": {
    "type": "Organization",
    "organization_id": "{orgId}"
  }
}
```

# POST /software-repository/{orgId}/{packageId}/version