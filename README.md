# Running trustify load tests

The goal is to have load tests, which can be re-run over time to see the evolution of Trustify's performance.

## Running it locally

After clone, run:

```bash
cp publish/baseline.json baseline/
```

Build the containers once:

```bash
podman compose -f compose.yaml build
```

Then run the test:

```bash
podman compose -f compose.yaml run loadtests
```

After the test has run, clean up:

```bash
podman compose -f compose.yaml down
```

Some of the large files are cached in a volume, it is possible to delete those volumes as well using:

```bash
podman compose -f compose.yaml down -v
```

## Wait, there is more

### Start a DB instance with an imported dump

To start up a database instance with the imported dump, run the following commands:

```bash
podman compose -f compose.yaml build
podman compose -f compose.yaml up trustify-migrate
```

### Connect a `psql` terminal to the database

```bash
podman compose -f compose.yaml build
podman compose -f compose.yaml up db-shell
```

### Excluding Bad Reports

1. Add filename to `publish/excluded-reports.txt`:  
   `report-2024-09-03T07-38-09.json`  # Wrong configuration - invalid dump
2. Run `./generate-manifest.sh` to regenerate the manifest
3. Open a PR to push the changes

### Add a marker on the chart

You can add marker on the chart, marking important events on the scale test, like switching to a newer dump.

1. Add an entry to `publish/markers.json`
2. Run `./generate-manifest.sh` to regenerate the manifest
3. Open a PR to push the changes

### Test changes to the dashboard locally

1. Make changes to the dashboard
2. Run `./generate-manifest.sh` to regenerate the manifest
3. Run a local webserver using (one of the following):
    * ```bash
      cd publish
      python -m http.server
      ```
    * ```bash
      miniserve publish/
      ```
