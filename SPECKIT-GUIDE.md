# Spec-Kit Guide for Claude Code (NichiDict Project)

## 🎯 Overview

Your NichiDict project is now set up with **spec-kit**, a toolkit for **Spec-Driven Development**. This guide shows you how to use it with Claude Code.

## 📁 What Was Installed

```
NichiDict/
├── .claude/
│   └── commands/              # Claude Code slash commands
│       ├── speckit.constitution.md
│       ├── speckit.specify.md
│       ├── speckit.clarify.md
│       ├── speckit.plan.md
│       ├── speckit.tasks.md
│       ├── speckit.implement.md
│       ├── speckit.analyze.md
│       └── speckit.checklist.md
├── .specify/
│   ├── memory/
│   │   └── constitution.md    # Project principles template
│   ├── scripts/
│   │   └── bash/              # Helper automation scripts
│   └── templates/             # Document templates
```

## 🔄 The Spec-Driven Development Workflow

Follow these steps in order with Claude Code:

---

### **STEP 1: Establish Your Constitution** ⚖️

**What it does**: Defines your project's core principles that guide all development decisions.

**In Claude Code, type:**

```
/speckit.constitution

Establish the NichiDict constitution with these principles:

1. **Swift-First Development**: 
   - Use Swift 6 with modern concurrency (async/await)
   - Prefer value types over reference types
   - Leverage Swift Package Manager for modular architecture

2. **Modular Architecture**: 
   - Features organized as Swift packages (like CoreKit)
   - Clear separation between logic and UI layers
   - Reusable components across iOS/macOS

3. **Test-Driven Development (TDD)**:
   - 80%+ test coverage for CoreKit modules
   - Unit tests must pass before implementation merge
   - UI tests for critical user flows

4. **Privacy & Offline-First**:
   - All dictionary data stored locally
   - No user tracking or analytics
   - Full functionality without network connection

5. **Performance Standards**:
   - Search results under 100ms for common queries
   - Smooth 60fps UI animations
   - Memory usage < 50MB for base dictionary

6. **Accessibility**:
   - Full VoiceOver support
   - Dynamic Type support for all text
   - Keyboard navigation support
```

**Output**: Creates `.specify/memory/constitution.md` with your project principles.

---

### **STEP 2: Create a Feature Specification** 📋

**What it does**: Creates a detailed, technology-agnostic specification for a new feature.

**Example - Adding Kanji Compound Search:**

```
/speckit.specify

Create a specification for advanced kanji compound word search functionality.

Users should be able to:
- Search for words by entering one or more kanji characters
- See results showing readings (hiragana/romaji), meanings, and JLPT levels
- Filter results by word type (noun, verb, adjective)
- Save favorite words to a local collection
- View example sentences for each word

Performance requirement: Display results within 100ms for queries with < 3 kanji.
The feature should work completely offline using a local SQLite dictionary database.
```

**Output**: Creates `specs/[feature-number]-[feature-name]/spec.md` with structured requirements.

---

### **STEP 3 (Optional): Clarify Requirements** 🔍

**What it does**: Asks structured questions to resolve ambiguities before planning.

```
/speckit.clarify

Review the kanji search specification and ask clarifying questions about:
- Edge cases (what happens with rare kanji?)
- UI/UX decisions (inline results vs modal?)
- Performance expectations for large result sets
- Data source and dictionary format
```

**When to use**: When your spec has ambiguities that could impact implementation.

**Output**: Updates spec.md with a "Clarifications" section containing answers.

---

### **STEP 4: Generate Implementation Plan** 🗺️

**What it does**: Creates a technical implementation plan with your specific tech stack.

```
/speckit.plan

Create an implementation plan for the kanji search feature using:

**Technology Stack:**
- Swift 6 with async/await for search operations
- SwiftUI for the UI layer
- SQLite with GRDB.swift for dictionary database
- Combine for reactive search-as-you-type
- SwiftData for favorites persistence

**Architecture:**
- Extend CoreKit with KanjiSearchService
- Create SearchViewModel with @Observable
- Build SearchResultsView with LazyVStack for performance
- Implement FavoritesManager for local storage

**Performance:**
- Use full-text search (FTS5) in SQLite
- Implement result pagination (50 items at a time)
- Cache recent searches in memory
- Debounce search input (300ms)

**Testing:**
- Unit tests for search algorithms
- Performance tests for 100ms requirement
- UI tests for search flow
```

**Output**: Creates multiple implementation detail documents:
- `plan.md` - Overall implementation plan
- `data-model.md` - Database schema
- `contracts/` - API specifications
- `research.md` - Technology research notes

---

### **STEP 5: Generate Actionable Tasks** ✅

**What it does**: Breaks down the plan into specific, ordered implementation tasks.

```
/speckit.tasks

Break down the kanji search implementation plan into actionable tasks.

Use TDD approach:
1. Write tests first
2. Implement minimum code to pass
3. Refactor

Include tasks for:
- Database schema migration
- Search service implementation
- ViewModel and UI components
- Integration tests
- Performance validation
```

**Output**: Creates `tasks.md` with ordered, dependency-aware task breakdown.

---

### **STEP 6: Implement** 🚀

**What it does**: Executes the implementation following your task plan.

```
/speckit.implement

Execute the implementation plan using TDD approach.
Run tests after each step and ensure all tests pass before proceeding.
```

**What happens:**
- Claude Code reads the task breakdown
- Executes tasks in order (respecting dependencies)
- Runs tests and validates each step
- Reports progress and handles errors

⚠️ **Important**: Claude Code will execute local CLI commands (e.g., `swift build`, `swift test`). Make sure you have the Swift toolchain installed.

---

## 🎨 Optional Enhancement Commands

### `/speckit.analyze` - Cross-Artifact Validation

**When to use**: After creating tasks, before implementing.

```
/speckit.analyze

Validate that the spec, plan, and tasks are consistent.
Check for missing requirements or contradictions.
```

**Output**: Consistency report showing alignment issues.

---

### `/speckit.checklist` - Quality Validation

**When to use**: After creating the plan.

```
/speckit.checklist

Generate quality checklists to validate:
- Requirements completeness
- Testability of acceptance criteria
- Alignment with constitution
```

**Output**: Checklist for manual review.

---

## 📖 Real-World Example Workflow

Here's a complete workflow for adding a new feature:

### 1️⃣ Establish Constitution (One-time setup)

```
/speckit.constitution

[Use the constitution example from STEP 1 above]
```

### 2️⃣ Specify New Feature

```
/speckit.specify

Add audio pronunciation support to NichiDict.

Users should be able to tap a speaker icon next to any word to hear its pronunciation.
Audio files should be bundled with the app for offline use.
Support both Tokyo and Osaka dialect variations where available.
Playback should be instant (< 50ms delay).
```

### 3️⃣ Create Implementation Plan

```
/speckit.plan

Implement audio pronunciation using:
- AVFoundation for audio playback
- Bundled MP3 files in Asset Catalog
- Audio caching layer in CoreKit
- SwiftUI Button with SF Symbol for UI
```

### 4️⃣ Generate Tasks

```
/speckit.tasks

Break down audio feature into TDD tasks with tests for:
- Audio file loading
- Playback manager
- Cache performance
- UI integration
```

### 5️⃣ Implement

```
/speckit.implement

Execute the audio pronunciation implementation.
```

---

## 🔧 Tips for Success

### ✅ Do:
- Start with a clear constitution
- Be specific in feature descriptions
- Include performance requirements in specs
- Use `/speckit.clarify` for ambiguous areas
- Let Claude Code execute the plan (trust the process)

### ❌ Don't:
- Skip the constitution step
- Include implementation details in specs (keep them technology-agnostic)
- Try to implement before planning
- Ignore failing tests

---

## 🛡️ Security Note

Consider adding `.claude/` to your `.gitignore` to prevent accidentally committing credentials:

```bash
echo ".claude/" >> .gitignore
```

---

## 📚 Project Structure After Using Spec-Kit

After creating a few features, your project will look like:

```
NichiDict/
├── .claude/
├── .specify/
├── specs/
│   ├── 001-kanji-compound-search/
│   │   ├── spec.md
│   │   ├── plan.md
│   │   ├── tasks.md
│   │   ├── data-model.md
│   │   └── contracts/
│   ├── 002-audio-pronunciation/
│   │   ├── spec.md
│   │   ├── plan.md
│   │   └── tasks.md
│   └── 003-favorites-sync/
├── Modules/
│   └── CoreKit/
└── NichiDict/
```

---

## 🚀 Getting Started

**Start now by establishing your constitution:**

```
/speckit.constitution

[Paste the constitution from STEP 1]
```

Then create your first feature spec! 🎉

---

## 📖 Resources

- [Spec-Kit GitHub](https://github.com/github/spec-kit)
- [Spec-Driven Development Guide](https://github.com/github/spec-kit/blob/main/spec-driven.md)

---

**Happy spec-driven development! 🚀**

