# Bundled knowledge

The static, read-only knowledge that ships with the app: the Firm schema (`schemas.firm`) plus one seed entity per fact/thing about Eigin. This is a real [Firm](https://github.com/42futures/firm) workspace so Firm CLI tools can load, build, and query it directly while authoring.

## Layout

One entity per file. The folder is the entity type; the filename stem is the
entity id — the same shape the app's `bundled/<type>/<id>.firm` virtual paths
take at runtime.

```
design/knowledge/
  schemas.firm            # the ontology (the one non-entity source)
  thing/eigin.firm        # thing.eigin
  fact/<id>.firm          # one file per fact
```

## How it reaches the app

With `just generate`, `eigin-tools` reads this workspace, validates it with Firm, and generates platform-specific code to include it.

## Editing

- Add a fact: drop a new `fact/<id>.firm` file. It gets bundled automatically.
- Edit content: change the `.firm` source and run `just generate`.
