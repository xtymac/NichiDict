#!/usr/bin/env swift

import Foundation

// Quick test script to demonstrate the new ranking behavior
// This would be run against a real database to verify results

let testCases = [
    ("star", "Should show: 星 → スター → えとわーる"),
    ("go", "Should show: 行く → 囲碁"),
    ("language", "Should show: 言語 → ランゲージ"),
    ("actor", "Should show: 俳優 → アクター"),
    ("eat", "Should show: 食べる before katakana")
]

print("=== English → Japanese Reverse Search Ranking Test Cases ===\n")

for (query, expected) in testCases {
    print("Query: '\(query)'")
    print("Expected: \(expected)")
    print("---")
}

print("\n=== Ranking Priorities ===")
print("1. Core native equivalents (星, 行く, 言語, 俳優)")
print("2. Parenthetical semantic matches")
print("3. Part-of-speech (verbs > nouns > other)")
print("4. Common frequency (≤5000)")
print("5. DEMOTED: Pure katakana loanwords")
print("6. Match quality (exact > prefix > contains)")
print("7. Frequency rank")
print("8. Created date & ID (tie-breaker)")
