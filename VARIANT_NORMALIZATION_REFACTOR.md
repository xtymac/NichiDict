# Variant Normalization Refactor

## Branch
`feature/jmdict-variant-normalization`

## Objective
Implement JMDict-based variant normalization and remove all hardcoded variant logic.

## Goals
- Replace hardcoded variant handling with JMDict-based normalization
- Remove all hardcoded variant logic from the codebase
- Improve maintainability by relying on JMDict data structure
- Ensure consistent variant handling across the application

## Current Status
- Branch created: `feature/jmdict-variant-normalization`
- Previous work stashed: Conjunction priority adjustments from `feature/n4-vocabulary-testing`

## Testing Plan
- [ ] Test variant normalization with various kanji forms
- [ ] Verify search results consistency
- [ ] Test reverse search functionality
- [ ] Validate against existing test cases
- [ ] Performance testing

## Notes
- This is a major refactor of the database sorting algorithm
- Will return to testing after implementation
- Previous branch `feature/n4-vocabulary-testing` is preserved with stashed changes

