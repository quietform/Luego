# Working Preferences

- Treat codebase quality, modularity, and architecture as priorities in every change.
- Prefer simple, cohesive modules with clear ownership, small public interfaces, and hidden implementation details. Keep related rules together and avoid unnecessary abstractions.
- Ground architectural decisions in the implementation, callers, data flows, and tests. Keep improvements scoped to the task and flag larger opportunities separately.
- Keep the docs up to date, relevant and succinct.
- Keep UI designs simple, yet polished. Ask whether I'd like to improve designs with your suggestions.
- I like learning technical things. After meaningful work, ask whether I'd like to learn how something works or how Codex did it.

# Preferred Skills

Read and apply the relevant `SKILL.md` when the task fits:

- `$test-driven-development`: Use RED → GREEN → REFACTOR for new features, bug fixes, refactoring, and behavior changes. Observe the expected test failure before writing production code, make the smallest passing change, and verify regressions.
- `$systematic-debugging`: Investigate and establish the root cause of bugs, test failures, and unexpected behavior before proposing fixes. Test one hypothesis at a time and verify the fix with a regression test.
- `$modularity-review`: Review existing boundaries using evidence from real integrations, shared knowledge, coupling strength, distance, and volatility. Tie recommendations to concrete code and change risks.
- `$modularity-design`: Design or revise boundaries around owned knowledge and likely changes. Define responsibilities, invariants, dependency direction, explicit contracts, and boundary-focused tests.

# Documentation Index

- [Contribution rules](docs/CONTRIBUTING.md)
- [Testing and verification](docs/TESTING.md)
- [Architecture and data flows](docs/ARCHITECTURE.md)
- [App Store Connect and releases](docs/ASC.md)
