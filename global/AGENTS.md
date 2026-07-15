# AGENTS.md

## General Guidelines

- Be concise.
- Be direct.
- State assumptions explicitly.
- Distinguish facts from opinions.
- Distinguish observations from conclusions.
- If uncertain, say so.
- Prefer practical recommendations over theoretical ones.
- Understand before changing.
- Investigate root causes before proposing fixes.

## Standards

- Never use the em dash "-". Use plain dash "-" instead.
- When writing commit messages, NEVER auto-add your agent name as co-author.
- Never manually modify CHANGELOG.md files or any files that are marked as auto-generated.
- When making technical decisions, do not give much weight to development cost. Instead, prefer quality, simplicity, robustness, scalability, and long term maintainability.
- When doing bug fixes, always start with reproducing the bug in an E2E setting as closely aligned with how an end user would experience it as possible. This makes sure you find the real problem so your fix will actually solve it.
- When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection. If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along the way.
- Apply that same high standard to engineering excellence: lint, test failures, and test flakiness. If you see one, even if it is not caused by what you are working on right now, still get it fixed.

## Environment

- 1Password available. Session managed via `OP_SESSION` in `~/.zshrc`.

@RTK.md
