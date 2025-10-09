<!--
SYNC IMPACT REPORT
==================
Version Change: 0.0.0 (template) → 1.0.0 (initial ratification)
Change Type: MAJOR - Initial constitution ratification

Modified Principles:
- NEW: Swift-First Development
- NEW: Modular Architecture
- NEW: Test-Driven Development (TDD)
- NEW: Privacy & Offline-First
- NEW: Performance Standards
- NEW: Accessibility

Added Sections:
- Core Principles (6 principles defined)
- Quality Standards
- Development Workflow
- Governance

Removed Sections:
- None (initial creation)

Templates Requiring Updates:
- ✅ .specify/templates/plan-template.md (validated - compatible)
- ✅ .specify/templates/spec-template.md (validated - compatible)
- ✅ .specify/templates/tasks-template.md (validated - compatible)

Follow-up TODOs:
- None - all placeholders resolved
-->

# NichiDict Constitution

## Core Principles

### I. Swift-First Development

NichiDict MUST be built using Swift 6 with modern language features and best practices:

- **Swift 6 Concurrency**: Use async/await for all asynchronous operations; avoid completion handlers and legacy patterns
- **Type Safety**: Prefer value types (struct, enum) over reference types (class) unless reference semantics required
- **Swift Package Manager**: All modular features MUST be organized as Swift packages for reusability and testability
- **Modern APIs**: Leverage latest Swift features (property wrappers, result builders, macros where appropriate)

**Rationale**: Swift 6's strict concurrency checking eliminates data races at compile time, and value types reduce memory management complexity. SPM enables modular architecture and cross-platform code reuse (iOS/macOS).

### II. Modular Architecture

Features MUST be organized as independent, composable Swift packages:

- **Package Structure**: Core functionality lives in packages (e.g., CoreKit) separate from app targets
- **Layer Separation**: Clear boundaries between logic (packages), data (persistence), and UI (SwiftUI views)
- **Reusability**: Packages MUST support both iOS and macOS with minimal platform-specific code
- **Dependency Management**: Packages declare explicit dependencies; avoid circular dependencies

**Rationale**: Modular packages enable independent testing, faster build times (incremental compilation), and code reuse across platforms. Clear separation of concerns reduces coupling and improves maintainability.

### III. Test-Driven Development (TDD) — NON-NEGOTIABLE

All CoreKit modules and critical features MUST follow strict TDD:

- **Coverage Target**: Minimum 80% test coverage for all CoreKit packages
- **Test-First**: Unit tests MUST pass before implementation merge
- **UI Testing**: Critical user flows MUST have automated UI tests (search, favorites, navigation)
- **Red-Green-Refactor**: Write failing test → Implement minimum code to pass → Refactor
- **Fast Tests**: Unit test suite MUST complete in under 10 seconds for rapid feedback

**Rationale**: TDD prevents regressions, documents expected behavior, and ensures code is testable by design. The 80% threshold balances thoroughness with pragmatism. Fast tests enable continuous verification during development.

### IV. Privacy & Offline-First

NichiDict MUST respect user privacy and function fully offline:

- **Local Storage**: All dictionary data, user preferences, and favorites MUST be stored locally
- **No Tracking**: No analytics, telemetry, or user behavior tracking
- **No Network Dependency**: Full dictionary functionality (search, lookup, favorites) MUST work without internet
- **Data Ownership**: Users own their data; export/import features for portability

**Rationale**: Privacy is a core value. Japanese language learners often study in offline environments (trains, planes). Local-first architecture eliminates server costs and data breach risks.

### V. Performance Standards

NichiDict MUST meet strict performance benchmarks:

- **Search Latency**: Common queries (< 3 kanji) MUST return results in under 100ms
- **UI Responsiveness**: All animations and transitions MUST maintain 60fps on target devices
- **Memory Efficiency**: Base dictionary data MUST use less than 50MB of memory
- **Launch Time**: App MUST launch to usable state in under 2 seconds (cold start)

**Rationale**: Instant search feedback is critical for learning flow. Smooth animations prevent user frustration. Low memory usage ensures compatibility with older devices and multitasking scenarios.

### VI. Accessibility

NichiDict MUST be fully accessible to all users:

- **VoiceOver Support**: All interactive elements MUST have descriptive labels and hints
- **Dynamic Type**: All text MUST scale with user-preferred text sizes
- **Keyboard Navigation**: Full app functionality MUST be accessible via keyboard shortcuts (macOS)
- **High Contrast**: UI MUST remain readable in high-contrast and reduced-transparency modes

**Rationale**: Language learning tools should be accessible to users with visual impairments or motor disabilities. Accessibility features benefit all users (e.g., Dynamic Type aids readability).

## Quality Standards

### Testing Requirements

- **Unit Tests**: All business logic, data models, and service layers
- **Integration Tests**: Database queries, file I/O, cross-module communication
- **UI Tests**: User flows for search, favorites, settings, and navigation
- **Performance Tests**: Search latency, memory usage, and UI responsiveness benchmarks
- **Edge Cases**: Empty states, large result sets, invalid input, offline mode

### Code Quality

- **SwiftLint**: All code MUST pass SwiftLint rules (configured in .swiftlint.yml)
- **Documentation**: Public APIs MUST include DocC-compatible documentation
- **Type Safety**: Avoid force-unwrapping (!), prefer optional binding and guard statements
- **Error Handling**: Use Result types or async throws; avoid silent failures

### Security

- **Input Validation**: Sanitize all user input before database queries or file operations
- **Secure Storage**: Use Keychain for sensitive data (if future features require it)
- **Dependency Auditing**: Regularly update dependencies to patch security vulnerabilities

## Development Workflow

### Feature Development Process

1. **Specification** (`/speckit.specify`): Define user-facing requirements (technology-agnostic)
2. **Clarification** (`/speckit.clarify`): Resolve ambiguities before implementation
3. **Planning** (`/speckit.plan`): Design technical approach, data models, and API contracts
4. **Task Generation** (`/speckit.tasks`): Break down into actionable, testable tasks
5. **Implementation** (`/speckit.implement`): Execute tasks following TDD
6. **Validation** (`/speckit.analyze`): Cross-artifact consistency check

### Code Review Requirements

- **Constitution Compliance**: Reviewer MUST verify adherence to all principles
- **Test Coverage**: No PR merged without tests meeting 80% threshold
- **Performance**: Reviewer MUST verify performance standards not regressed
- **Accessibility**: Reviewer MUST test VoiceOver and Dynamic Type support

### Commit Guidelines

- **Conventional Commits**: Use format: `type(scope): description` (e.g., `feat(search): add kanji compound filtering`)
- **Types**: feat, fix, refactor, test, docs, perf, chore
- **Atomic Commits**: One logical change per commit
- **Build Pass**: All commits MUST pass tests and build without warnings

## Governance

### Amendment Process

This constitution governs all NichiDict development. Amendments require:

1. **Proposal**: Document proposed change with rationale
2. **Impact Analysis**: Assess effect on existing code, tests, and documentation
3. **Approval**: Project maintainer approval
4. **Migration Plan**: For breaking changes, define migration steps
5. **Version Update**: Increment version per semantic versioning (below)

### Versioning Policy

Constitution versions follow semantic versioning:

- **MAJOR**: Principle removed, redefined, or made non-negotiable (e.g., 1.0.0 → 2.0.0)
- **MINOR**: New principle added or existing principle materially expanded (e.g., 1.0.0 → 1.1.0)
- **PATCH**: Clarifications, wording improvements, typo fixes (e.g., 1.0.0 → 1.0.1)

### Compliance Review

- **PR Review**: All pull requests MUST verify compliance with this constitution
- **Justification Required**: Deviations MUST include documented rationale and simpler alternatives considered
- **Quarterly Audit**: Review constitution relevance and update if project needs evolved

### Runtime Guidance

For day-to-day development guidance beyond this constitution, refer to:

- **Spec-Driven Workflow**: `.claude/commands/speckit.*.md` for feature development
- **Templates**: `.specify/templates/` for spec, plan, and task structures
- **Scripts**: `.specify/scripts/bash/` for automation helpers

**Version**: 1.0.0 | **Ratified**: 2025-10-08 | **Last Amended**: 2025-10-08
