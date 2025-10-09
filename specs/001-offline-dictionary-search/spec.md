# Feature Specification: Offline Dictionary Search

**Feature Branch**: `001-offline-dictionary-search`
**Created**: 2025-10-08
**Status**: Draft
**Input**: User description: "Create a specification for NichiDict's core 'offline dictionary search' feature. Users should be able to: Search for words using kanji, kana, or romaji; View meanings, readings, part of speech, and frequency rank; See pitch accent and example sentences; Work completely offline (data stored in bundled seed.sqlite); Achieve <200ms response time for common queries"

## Clarifications

### Session 2025-10-08

- Q: When multiple entries match a search query (e.g., searching "日" returns hundreds of words), how should results be ordered? → A: Match type + frequency (exact > prefix > contains, then frequency within each group). Future upgrade path to relevance score algorithm.
- Q: The spec mentions "appropriate debouncing" for real-time search. What is the debounce delay to balance responsiveness with performance? → A: Adaptive (150ms for <3 chars, 300ms for 3+ chars)
- Q: Which specific notation system should be used for pitch accent visual notation? → A: Downstep arrows (た↓べる - shows pitch drops with ↓)
- Q: What is the minimum supported device specification for "target devices" mentioned in SC-006? → A: iOS 16+ on iPhone 11 / Intel Mac 2018+
- Q: Which romanization system should be used for romaji input/output consistency? → A: Flexible input, Hepburn output (accept both Hepburn and Kunrei-shiki for search, display Hepburn)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Basic Word Lookup (Priority: P1)

A user opens NichiDict and searches for a Japanese word to understand its meaning and reading. They can type in any writing system (kanji, hiragana, katakana, or romaji) and instantly see results with meanings and pronunciation.

**Why this priority**: This is the absolute core MVP - the fundamental value proposition of a dictionary. Without basic lookup, the app has no purpose. This delivers immediate value: "I see a word, I want to know what it means."

**Independent Test**: Can be fully tested by launching the app, typing "食べる" or "taberu" into the search box, and verifying that results appear with English meanings and readings. Delivers complete value even without any other features.

**Acceptance Scenarios**:

1. **Given** the app is open, **When** user types "桜" in the search box, **Then** results display showing "sakura", meanings ("cherry blossom", "cherry tree"), and part of speech (noun)
2. **Given** the app is open, **When** user types "たべる" (hiragana), **Then** results display showing "食べる", romaji "taberu", and meanings ("to eat")
3. **Given** the app is open, **When** user types "taberu" (romaji), **Then** results display showing "食べる", hiragana "たべる", and meanings ("to eat")
4. **Given** the app is open with no network connection, **When** user searches for any word, **Then** results display instantly from local database without errors
5. **Given** user types a partial word "たべ", **When** typing continues, **Then** results update in real-time as they type

---

### User Story 2 - Detailed Entry Information (Priority: P2)

A language learner needs comprehensive information about a word to use it correctly. After finding a word, they view detailed information including pitch accent patterns, frequency rank (how common the word is), and part-of-speech tags to understand grammar.

**Why this priority**: This elevates the dictionary from basic translation to a learning tool. Pitch accent is critical for natural pronunciation, and frequency rank helps learners prioritize which words to study first. This is essential for serious learners but the app is still useful without it.

**Independent Test**: Can be tested by searching for "食べる", tapping the result, and verifying that a detail view shows pitch accent notation (e.g., "た↓べる"), frequency rank (e.g., "Top 500"), and detailed part-of-speech (e.g., "Ichidan verb, transitive"). Delivers value independently of other features.

**Acceptance Scenarios**:

1. **Given** user has searched for "食べる", **When** they tap the search result, **Then** detail view displays pitch accent pattern with visual notation
2. **Given** user is viewing word details, **When** the screen loads, **Then** frequency rank is displayed (e.g., "Top 500 most common words")
3. **Given** user is viewing word details, **When** the screen loads, **Then** complete part-of-speech information is shown (e.g., "Ichidan verb, transitive verb")
4. **Given** user is viewing a rare word, **When** frequency rank is not available, **Then** display shows "Frequency: Uncommon" or similar indicator
5. **Given** user is viewing details offline, **When** no network is available, **Then** all pitch accent, frequency, and grammatical information loads from local database

---

### User Story 3 - Example Sentences (Priority: P3)

A learner wants to see how a word is used in context to understand nuance and proper usage. After looking up a word, they browse example sentences showing the word in real Japanese sentences with English translations.

**Why this priority**: Example sentences demonstrate usage patterns and collocations that pure definitions cannot capture. This is valuable for intermediate/advanced learners but beginners can learn effectively with just definitions and readings. This enhances learning but is not blocking for basic dictionary functionality.

**Independent Test**: Can be tested by searching for "食べる", opening the detail view, scrolling to the examples section, and verifying that multiple Japanese sentences with English translations are displayed. Delivers independent value: "I want to see this word used in a real sentence."

**Acceptance Scenarios**:

1. **Given** user is viewing word details for "食べる", **When** they scroll to the examples section, **Then** at least 3 example sentences are displayed with Japanese text and English translations
2. **Given** user is viewing example sentences, **When** they read each sentence, **Then** the target word "食べる" is visually highlighted within the sentence
3. **Given** user is viewing examples for a common word, **When** examples load, **Then** sentences are ordered by frequency or simplicity (beginner-friendly first)
4. **Given** user is viewing examples for a rare word, **When** examples are not available, **Then** display shows "No example sentences available" message
5. **Given** user is offline, **When** viewing example sentences, **Then** all examples load instantly from bundled database without network errors

---

### Edge Cases

- **Empty search query**: What happens when user submits an empty search box? System should display a prompt like "Enter a word to search" or show recent searches.
- **No results found**: When user searches for a word not in the dictionary (e.g., "xyzabc"), system displays "No results found" with suggestions like "Check spelling" or "Try searching in different writing system".
- **Very long search queries**: When user types >100 characters, system should handle gracefully (limit input or show warning).
- **Partial kanji input**: What happens when user types a single kanji that appears in hundreds of words (e.g., "日")? System should limit results to top 50-100 most relevant/frequent matches and show "Showing top 50 results" message.
- **Database corruption or missing**: If seed.sqlite is corrupted or missing, app should detect on launch and display clear error: "Dictionary database is missing or corrupted. Please reinstall the app."
- **Special characters**: When user searches with special characters (!@#$%), system should sanitize input and search safely without SQL injection vulnerabilities.
- **Simultaneous rapid searches**: When user types very fast or changes search rapidly, system should debounce input and cancel previous queries to avoid performance issues.
- **Memory constraints**: On older devices with limited memory, when displaying hundreds of results, system should paginate or virtualize list to prevent crashes.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST accept search input in kanji, hiragana, katakana, and romaji writing systems (romaji: flexible input accepting both Hepburn and Kunrei-shiki romanization)
- **FR-002**: System MUST return search results within 200ms for common queries (< 3 characters)
- **FR-003**: System MUST display word meanings in English, readings in hiragana/katakana and romaji (Hepburn romanization for output), and part of speech tags
- **FR-004**: System MUST operate completely offline using bundled seed.sqlite database
- **FR-005**: System MUST display pitch accent patterns using downstep arrow notation (e.g., た↓べる) for words where data is available
- **FR-006**: System MUST display frequency rank information (e.g., "Top 500", "Common", "Rare") when available
- **FR-007**: System MUST display example sentences with Japanese text and English translations for words where available
- **FR-008**: System MUST highlight the searched word within example sentences
- **FR-009**: System MUST handle searches with no results gracefully with clear messaging
- **FR-010**: System MUST sanitize search input to prevent SQL injection or database errors
- **FR-011**: System MUST limit result sets to prevent performance degradation (max 100 results displayed)
- **FR-014**: System MUST rank search results by match type (exact match > prefix match > contains match), then by frequency rank within each match type group
- **FR-012**: System MUST provide real-time search results as user types with adaptive debouncing (150ms for queries <3 characters, 300ms for 3+ characters)
- **FR-013**: System MUST support iOS 16+ (iPhone 11 and newer) and macOS (Intel Mac 2018+ and Apple Silicon) using shared CoreKit package

### Key Entities

- **Dictionary Entry**: Represents a Japanese word with unique identifier, headword (kanji/kana), readings (hiragana, romaji), frequency rank, and pitch accent pattern. Primary searchable entity.
- **Word Sense**: Represents a distinct meaning of a dictionary entry. Includes English definitions, part-of-speech tags, usage notes. Relationship: one Entry has many Senses.
- **Example Sentence**: Represents a sample sentence demonstrating word usage. Includes Japanese sentence text, English translation, and reference to the word it exemplifies. Relationship: one Sense has many Examples.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can successfully find any common word (top 5000 frequency) in under 3 interactions (type + search + tap result)
- **SC-002**: Search queries return results in under 200ms for 95% of searches (measured via performance tests)
- **SC-003**: App functions with 100% feature parity offline vs online (no network-dependent features for core search)
- **SC-004**: Users can view complete word information (meaning, reading, pitch accent, frequency, examples) in a single detail view without navigating to multiple screens
- **SC-005**: Search accuracy: 95%+ of searches for valid Japanese words return the correct entry in the top 3 results
- **SC-006**: App launches to searchable state in under 2 seconds (cold start on minimum supported devices: iPhone 11 / Intel Mac 2018+)
- **SC-007**: Database bundle size remains under 100MB to keep app download size reasonable
