---
description: Deliberately broken skill (no name field) used by the linter self-test. Never installed.
---

# Bad Skill (fixture)

This file intentionally omits the `name:` frontmatter so `tests/run.sh` has something the
linter must reject. If the linter ever passes this, the linter is broken.
