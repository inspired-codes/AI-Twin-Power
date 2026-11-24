# AI Twin Power

Get better results from **two AI models** by letting them think independently, argue with evidence and align on one recommendation.

| Part | What it is |
|---|---|
| [Twin-Power.md](Twin-Power.md) | The guide: patterns, prompts and rules for the user and the AI models. Works with any two models. |
| [GHOST-BUS.md](GHOST-BUS.md) | Optional: how agents on one machine message each other directly. |
| [bin/ghost](bin/ghost) | The Ghost Bus script. |
| [tests/ghost-test.sh](tests/ghost-test.sh) | Its tests. |

## Use the guide only

No installation needed.

1. Pick a pattern in [Twin-Power.md](Twin-Power.md#3-choose-a-pattern).
2. Copy the matching [prompt](Twin-Power.md#prompts-to-copy) and fill it in.
3. Send it to both models. If a model can't open the file, paste the guide too.
4. Carry the answers between them, or let them use the Ghost Bus.

## Use it with the Ghost Bus

For two AI agents that can run shell commands on the same machine, such as Claude Code (`claude`) and Antigravity (`agy`).

**Requirements:** Linux, `bash`, `jq`, `flock` (util-linux) and `git`.

**1. Create a bus** in the folder that holds your projects:

```bash
git clone https://github.com/inspired-codes/AI-Twin-Power.git
mkdir -p ~/.local/bin
ln -s "$PWD/AI-Twin-Power/bin/ghost" ~/.local/bin/ghost    # must be on your PATH
cd ~/Workspace
ghost init
```

**2. Tell both agents about it**, for example in `CLAUDE.md` and in the other agent's instruction file:

```text
Work with the other agent as described in <path>/AI-Twin-Power/Twin-Power.md.
Talk over the Ghost Bus as described in <path>/AI-Twin-Power/GHOST-BUS.md.
Your name on the bus is: claude
```

**3. Let both agents listen** before the first message is sent. Each runs its own command as an attached background task, inside the project folder:

```bash
ghost wait claude
ghost wait agy
```

**4. Talk**, also from inside the project folder:

```bash
ghost send human all message "Two-round debate: SQLite or PostgreSQL? See docs/db.md"
ghost send claude agy question "Which load do you assume?" --ref docs/db.md:10-20
ghost status
ghost log
```

Optional: `ghost install` in a git repo posts every commit to the bus.

## Limits

- **One machine, one Linux user.** The bus is plain files. There is no network and no encryption.
- **No authentication.** Anyone who can write to the bus can send under any name. Never put secrets on it.
- **Cooperative locks.** They only work if every agent follows the rules.
- **Two models can share the same mistake.** Verify important results.

## Tests

```bash
bash tests/ghost-test.sh
```

## License

AI Twin Power is licensed under the [GNU Affero General Public License v3.0](LICENSE.txt). If you run a modified version as a network service, the AGPL requires you to offer its source to your users.
