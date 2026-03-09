# GitLab Artifact Cleanup

Bash script to delete all job artifacts of a GitLab project via the REST API.

## Background

GitLab's built-in `DELETE /api/v4/projects/:id/artifacts` bulk-delete endpoint is extremely slow and unreliable. This script works around the issue by fetching all jobs with artifacts and sending individual DELETE requests per job.

## Prerequisites

- `bash` (4.0+)
- `curl`
- [`jq`](https://jqlang.github.io/jq/)
- GitLab Personal Access Token with `api` scope

## Usage

```bash
./cleanup-artifacts.sh -t TOKEN -u URL -p PROJECT_ID [-d]
```

### Parameters

| Flag | Description | Required |
|------|------------|----------|
| `-t` | GitLab Private/Personal Access Token | Yes |
| `-u` | GitLab instance URL (e.g. `https://gitlab.example.com`) | Yes |
| `-p` | Numeric project ID | Yes |
| `-d` | Dry-run: only show what would be deleted | No |
| `-h` | Show help | No |

### Examples

Preview what will be deleted:

```bash
./cleanup-artifacts.sh -t glpat-xxxxxxxxxxxx -u https://gitlab.example.com -p 42 -d
```

Actually delete artifacts:

```bash
./cleanup-artifacts.sh -t glpat-xxxxxxxxxxxx -u https://gitlab.example.com -p 42
```

## How It Works

1. All jobs are fetched via paginated `GET /api/v4/projects/:id/jobs` requests (100 per page, oldest first)
2. Jobs with existing artifacts are filtered (`artifacts` array is non-empty)
3. For each matching job, `DELETE /api/v4/projects/:id/jobs/:job_id/artifacts` is called
4. Progress and results are printed live to the console

### Example Output

```bash
Fetching jobs with artifacts for project 42...
  API: https://gitlab.example.com/api/v4/projects/42/jobs
  Page 1: fetching... 100 jobs, 12 with artifacts
  Page 2: fetching... 100 jobs, 3 with artifacts
  Page 3: fetching... 45 jobs, 0 with artifacts
Scanned 245 jobs across 3 page(s).
Found 15 jobs with artifacts. Deleting...
  [1/15] Job #1234 — deleted
  [2/15] Job #1235 — deleted
  ...
Done. 15 deleted, 0 failed.
```

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | All artifacts deleted successfully (or none found) |
| `1` | At least one DELETE request failed |

## Creating a Token

1. GitLab -> User Settings -> Access Tokens
2. Scope: `api`
3. Copy the token and pass it via `-t`

## Finding the Project ID

The numeric project ID is shown on the project overview page in GitLab below the project name, or under Settings -> General.
