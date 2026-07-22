# Versioning

Onbii Apple is pre-release.

Until the implementation has stable releases, versioning may remain informal. Once releases begin, this repository should use Semantic Versioning 2.0.0:

```text
MAJOR.MINOR.PATCH
```

## Major Releases

A major version indicates incompatible changes to public behaviour, supported bundle handling, app data expectations, or developer-facing APIs.

## Minor Releases

A minor version introduces backwards-compatible functionality.

Examples include:

- new capture surfaces;
- new import paths;
- new optional metadata;
- new preview or inspection capabilities;
- backwards-compatible package APIs.

## Patch Releases

Patch releases include backwards-compatible fixes, documentation improvements, and internal maintenance.

## Relationship To The Spec

The Onbii specification has its own versioning policy in [`docs/spec/VERSIONING.md`](./docs/spec/VERSIONING.md).

Implementation releases should state which specification version or commit they are intended to support.
