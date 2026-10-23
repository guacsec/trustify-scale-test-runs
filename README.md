# Trustify performance test runs

Repeatable load tests and historical performance reports for
[Trustify](https://github.com/guacsec/trustify).

**All active performance tests use Python-based [Locust](https://locust.io/).**
The test code and report generator live in Trustify's
[`tools/perf`](https://github.com/guacsec/trustify/tree/main/tools/perf) directory.
This repository provides the container stack, GitHub Actions workflows, and
published results.

## Dashboards

- [All performance tests](https://guacsec.github.io/trustify-scale-test-runs/perf/)
- [Daily main-branch tests](https://guacsec.github.io/trustify-scale-test-runs/perf/daily/)
- [Pull request tests](https://guacsec.github.io/trustify-scale-test-runs/perf/pr/)
- [Release-branch tests](https://guacsec.github.io/trustify-scale-test-runs/perf/branches/)

## How tests run

The [performance workflow](.github/workflows/trustify-perf.yaml):

1. Checks out this repository and the selected Trustify revision.
2. Builds Trustify and starts PostgreSQL 17, Keycloak, and the Trustify API using
   [Compose](compose.yaml).
3. Prepares the dataset, applies database migrations, and runs `VACUUM ANALYZE`.
4. Runs Locust from the selected Trustify checkout's `tools/perf` directory in a
   Python 3.13 container, using OIDC client credentials.
5. Collects container logs, stops the stack, and uploads results and logs as
   workflow artifacts.
6. On a successful run, generates dashboards, commits results under
   `publish/perf/` to `main`, and deploys `publish/` to GitHub Pages.

The defaults are **10 concurrent users**, a **spawn rate of 2 users/second**, a
**10-minute duration**, and **no wait between requests**. CI currently installs
Locust `2.37.5` and json5 `0.12.0`. Performance runs use the self-hosted runner
group `perf` and are queued to avoid overlapping runs.

### Run modes

| Mode | Trigger | Trustify revision | Published results |
| --- | --- | --- | --- |
| `daily` | Every day at 04:00 UTC, or manual dispatch | `main` by default | `publish/perf/daily/` |
| `branch` | Release-branch scheduler, or manual dispatch | Required `branch` input | `publish/perf/branches/<branch-slug>/daily/` |
| `pr` | Dispatch from Trustify's PR workflow, or manual dispatch | Required `source_sha` from `source_repository` | `publish/perf/pr/` |

The [release-branch scheduler](.github/workflows/trustify-branch-perf.yaml) also
runs daily at 04:00 UTC and dispatches tests for `release/0.6.z` and
`release/0.7.z`. Edit its branch matrix to change that list. Dashboard slugs drop
the `release/` prefix and replace remaining `/` characters with `-`.

For PR tests, comment `/perf-test` on a Trustify pull request. The dispatch is
handled by the Trustify repository; see its
[performance testing documentation](https://github.com/guacsec/trustify/tree/main/tools/perf#ci-workflows-and-dashboards)
for permissions and setup. Manual PR dispatch requires `source_repository`,
`source_sha`, and `pr_number`; `source_ref` supplies the branch name for metadata.

Daily and branch runs use `--exit-code-on-error 0` so request failures can still
be published for inspection. PR runs retain Locust's error exit status.

### Datasets

- **`full` (default):** restores the database and storage snapshot
  `20260317T023702Z` from the Trustify dump bucket. Locust uses
  `tools/perf/etc/scenarios/main/full-20260317T023702Z.json5` in the Trustify
  checkout for snapshot-specific IDs.
- **Dataset ZIP:** accepts a ZIP filename such as `ds3.zip`, or
  `etc/datasets/ds3.zip`, from the selected Trustify checkout. The workflow starts
  with an empty database, applies migrations, and uploads the ZIP through
  `/api/v3/dataset` before testing. If only the matching dataset source directory
  exists, the workflow creates the ZIP. No snapshot scenario file is selected.

### Trigger a run manually

Use **Actions → Trustify performance tests → Run workflow**, or the GitHub CLI:

```bash
# Default snapshot, main branch, 10 minutes
gh workflow run trustify-perf.yaml --repo guacsec/trustify-scale-test-runs \
  --ref main -f mode=daily

# Release branch
gh workflow run trustify-perf.yaml --repo guacsec/trustify-scale-test-runs \
  --ref main -f mode=branch -f branch=release/0.7.z

# Short run with a smaller dataset
gh workflow run trustify-perf.yaml --repo guacsec/trustify-scale-test-runs \
  --ref main -f mode=daily -f dataset=etc/datasets/ds3.zip -f duration=1m
```

`duration` must be a positive integer followed by `s`, `m`, `h`, or `d`, such as
`30s`, `10m`, or `2h`.

## Run Locust locally

The following uses Docker Compose and runs Python inside a container, matching
the CI test runner. Run these commands from this repository's root. Keep a
Trustify checkout alongside it at `../trustify`, or clone one:

```bash
git clone https://github.com/guacsec/trustify.git ../trustify
```

### Start the snapshot-backed stack

```bash
docker compose -f compose.yaml build --build-arg rev=main trustify-migrate trustify
docker compose -f compose.yaml up -d --wait trustify
docker compose -f compose.yaml exec -T postgres psql \
  -U postgres -d trustify -v ON_ERROR_STOP=1 -c 'VACUUM ANALYZE;'
```

The first run builds Trustify, downloads the database and storage dumps, imports
them, runs migrations, and initializes Keycloak. The API is exposed on
`http://localhost:8080`. PostgreSQL and Trustify have resource limits of 2 CPUs /
2 GiB and 3 CPUs / 2 GiB respectively; Keycloak and the build need additional
resources.

To test another revision, check it out in `../trustify` and set the matching
`rev` build argument above to a branch, commit, or `pr/<number>`.

### Run the Python tests

Connect Locust to the Compose network so it can reach both Trustify and the
configured Keycloak issuer:

```bash
trustify_container=$(docker compose -f compose.yaml ps -q trustify)
network=$(docker inspect --format '{{range $name, $network := .NetworkSettings.Networks}}{{$name}}{{end}}' "$trustify_container")

docker run --rm \
  --network "$network" \
  --volume "$PWD/../trustify/tools/perf:/perf" \
  --workdir /perf \
  --env ISSUER_URL=http://keycloak:8080/realms/trustify \
  --env CLIENT_ID=walker \
  --env CLIENT_SECRET=R8A6KFeyxJsMDBhjfHbpZTIF0GWt43HP \
  --env TOOLS_PERF_SCENARIO_FILE=etc/scenarios/main/full-20260317T023702Z.json5 \
  --env TOOLS_PERF_WAIT_TIME_FROM=0 \
  --env TOOLS_PERF_WAIT_TIME_TO=0 \
  python:3.13-slim sh -ec '
    pip install --disable-pip-version-check --no-cache-dir "locust==2.37.5" "json5==0.12.0"
    mkdir -p out
    exec locust --host http://trustify:8080 -u 10 -r 2 -t 10m --headless \
      --html=out/report.html --csv=out/results --csv-full-history
  '
```

The client secret above is the local test credential configured in
`compose.yaml`. Results are written to `../trustify/tools/perf/out/`. Use `-t 1m`
for a shorter run. See the
[Locust test documentation](https://github.com/guacsec/trustify/tree/main/tools/perf)
for test selection, interactive runs, and adding tests.

### Inspect and clean up

```bash
# Open a psql session against the prepared database
docker compose -f compose.yaml run --rm db-shell

# View service logs
docker compose -f compose.yaml logs

# Stop containers, keeping database, storage, and download-cache volumes
docker compose -f compose.yaml down

# Remove all volumes as well, including cached downloads
docker compose -f compose.yaml down -v
```

Existing database and storage volumes are reused locally. Use the volume cleanup
command before starting again when a fresh snapshot restore is required.

## Results and dashboard development

Each CI run includes a Locust HTML report, CSV statistics, and `metadata.json`
with the dataset, scenario, tested revision, and workflow URL. PR metadata also
includes the pull request URL. Locust results and container logs are retained as
workflow artifacts for 14 days.

Published runs live under `publish/perf/<mode-path>/runs/<run-id>/`; CSV files are
gzip-compressed during publishing. Dashboards are generated with
`tools/perf/locust_report.py` from Trustify `main`.

With the sibling Trustify checkout, rebuild the daily dashboard locally:

```bash
python3 ../trustify/tools/perf/locust_report.py index \
  publish/perf/daily/runs -o publish/perf/daily --prune \
  --title "Trustify load tests" --target "trustify (scale snapshot, CI)"
```

Preview the published site:

```bash
python3 -m http.server 8000 --directory publish
```

Open `http://localhost:8000/perf/`.


## Repository checks

[CI](.github/workflows/ci.yaml) lints GitHub Actions workflows with actionlint,
checks shell scripts with ShellCheck, and validates `compose.yaml` with
`docker compose config -q` on pull requests and pushes to `main`.
