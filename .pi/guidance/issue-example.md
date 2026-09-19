# Knowledge search finds nothing for words containing æ/ø/å

## Problem

Knowledge search returns no results for queries containing Danish
letters, even when the documents with those words are indexed. 

### Expected

Words match regardless of how special characters are normalized in the query.
Both "træ" and "trae" should find the same document.

### Actual

No results for the accented form. Accented words appear to be tokenized
differently between indexing and querying.

### Steps to reproduce

1. Add a document containing "træ" to the knowledge base.
2. Search the knowledge base for "træ": no results.
3. Search for "trae": document found.

### Suspected cause

The normalization step before embedding most likely strips non-ASCII
characters (confirm where in the ingest path before changing anything).

### Impact

Danish is one of our primary locales. For a large set of everyday words, knowledge search is effectively broken.

## Done when

- A document containing "træ" is found when searching "træ".
- A regression test covers æ/ø/å in both indexed documents and queries.

<!--
glab issue create \
  --title "Knowledge search finds nothing for words containing æ/ø/å" \
  --description "$(cat .pi/tmp/issue.md)" \
  --label "bug,priority::high,ux"
-->
