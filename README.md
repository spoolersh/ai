# Spooler for AI agents

Agent Skills for [Spooler](https://spooler.sh), the message queue, in the
[Agent Skills](https://agentskills.io) format.

| Skill | Teaches |
| --- | --- |
| [`spooler`](skills/spooler/SKILL.md) | the HTTP API and the delivery contract: leases, settles, dedup, delays, failed messages, queue settings, error kinds |
| [`spooler-go`](skills/spooler-go/SKILL.md) | the Go SDK, [`github.com/spoolersh/spooler-go`](https://github.com/spoolersh/spooler-go) |
| [`spooler-cli`](skills/spooler-cli/SKILL.md) | the `spooler` command line tool, [`spoolersh/spooler-cli`](https://github.com/spoolersh/spooler-cli) |

## Install

With the [`skills`](https://github.com/vercel-labs/skills) CLI, into the
current project (`-g` for every project):

```sh
npx skills add spoolersh/ai                      # all three
npx skills add spoolersh/ai --skill spooler-go   # one
```

Without it, copy a skill directory into your agent's skills folder
(`.claude/skills/`, `.agents/skills/` or the equivalent).

Update with `npx skills update`.

## Where the skills come from

`spooler-go` and `spooler-cli` are owned by their repositories, at
`skills/spooler-go/` in [spooler-go](https://github.com/spoolersh/spooler-go)
and `skills/spooler-cli/` in
[spooler-cli](https://github.com/spoolersh/spooler-cli), where tests keep
them in step with the code; the copies here are mirrors, refreshed from
each repository's latest release tag by the Mirror workflow
(`scripts/mirror.sh`), never edited here. Each installs from its own
repository too, as `npx skills add spoolersh/spooler-go`. `spooler` is published
from the product's repository next to its API spec: every bound and plan
limit it states is rendered from the spec and the plan catalog, so it is
not edited here either.

## What the skills say

Every statement in a skill is checkable with an API key and `curl`
against the public docs at https://docs.spooler.sh, which are the
contract. The skills restate the parts an agent needs in context and link
to the docs for the rest; they never describe unshipped behaviour.

The local evaluation image `spoolersh/memspoold` is free for development
and testing under the Spooler Local Evaluation License.
