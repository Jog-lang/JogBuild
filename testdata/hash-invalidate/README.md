# Content-hash cache invalidation

Same `version` repack must replace `JOG_CACHE/mod/<name>/<ver>/` when the archive `hash` changes.

```bash
export JOG_CACHE=/tmp/jog-cache-hash-demo
rm -rf "$JOG_CACHE"
jog-build pack testdata/hash-invalidate/lib -o testdata/hash-invalidate/out/hashlib-0.1.0.jogz
# edit lib.jog, pack again with same version, then:
jog-build build testdata/hash-invalidate/app -o /tmp/hashapp
```
