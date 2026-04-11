# Feature Specification: [Feature Name]

**Status**: Draft | In Review | Approved | In Progress | Complete
**Priority**: P0 | P1 | P2
**PRD Reference**: Section [X]
**Author**: [Name]
**Last Updated**: [YYYY-MM-DD]

## Overview
Brief description of the feature.

## User Stories
1. As a [user], I want [action] so that [benefit]

## Acceptance Criteria
- [ ] AC1: [Specific, testable criterion]
- [ ] AC2: …

## Technical Design

### Architecture
How this feature fits into the overall architecture.

### Data Flow
Step-by-step: input → processing → output.

### APIs Used
- `SomeFramework.someAPI` — why we chose it
- `AnotherFramework.otherAPI` — fallback if the first fails

### Data Models
```swift
struct FeatureModel {
    // …
}
```

## UI / UX
- Menu-bar changes
- HUD changes
- Settings changes

## Edge Cases
- [Case and how to handle]

## Testing Plan
- Unit tests for pure logic
- Manual test matrix for system integration

## Rollout
- [ ] Behind a settings toggle until proven stable
- [ ] Default on for [user type] only
- [ ] Default on for everyone

## Open Questions
- [ ] Question 1?
