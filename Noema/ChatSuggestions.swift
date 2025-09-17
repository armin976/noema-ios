// ChatSuggestions.swift
// Centralized list of starter prompts and simple rotation logic.

import Foundation

struct ChatSuggestions {
    // 30+ concise, useful mobile-friendly prompts
    static let all: [String] = [
        "Summarize the latest news in 3 bullet points.",
        "Give me 3 healthy lunch ideas I can make fast.",
        "Explain this like I’m 12: how does a VPN work?",
        "Draft a polite email to reschedule a meeting.",
        "Help me plan a 3‑day trip to Tokyo on a budget.",
        "Create a 20‑minute full‑body workout with no equipment.",
        "What are 5 interview questions for a product manager?",
        "Turn this into a to‑do list: clean kitchen, pay rent, call mom.",
        "Write a short bio (2–3 sentences) for LinkedIn.",
        "Explain pros and cons of buying vs leasing a car.",
        "Brainstorm 5 app ideas for students.",
        "Rewrite this to be friendlier: ‘Your request was denied.’",
        "What’s a quick weeknight dinner using chicken and rice?",
        "Suggest study techniques for learning a new language.",
        "Create a packing checklist for a weekend hike.",
        "Explain the difference between RAM and storage simply.",
        "Give 3 tips to improve my sleep routine.",
        "How do I negotiate a salary increase—key points only.",
        "Draft an agenda for a 30‑minute team sync.",
        "Summarize the book ‘Atomic Habits’ in 5 bullets.",
        "What are 3 simple mindfulness exercises I can try today?",
        "Help me write a compelling app store description.",
        "Outline a 7‑day beginner running plan.",
        "Explain end‑to‑end encryption in simple terms.",
        "Turn this note into an organized outline: weekend trip to Paris.",
        "What’s a fast way to back up my iPhone photos?",
        "Write a friendly reminder to pay an overdue invoice.",
        "Give 5 icebreaker questions for a new team meeting.",
        "Suggest 3 ways to stay focused while studying.",
        "Translate this to Spanish and keep the tone casual: ‘See you soon!’",
        "Help me prioritize tasks for a busy day.",
        "Explain 2FA and why it matters in one paragraph.",
        "Create a grocery list for 3 easy dinners this week.",
        "How can I reduce phone distractions without missing important alerts?",
        "Suggest 3 warm‑up stretches before a run.",
        "Give an example of a SMART goal for fitness."
    ]

    private static let shuffledKey = "ChatSuggestions.Shuffled"
    private static let indexKey = "ChatSuggestions.Index"

    /// Returns 3 suggestions, rotating through a persisted shuffled list.
    /// When a full cycle completes, the list is reshuffled to keep it fresh.
    static func nextThree() -> [String] {
        let d = UserDefaults.standard
        var shuffled = d.stringArray(forKey: shuffledKey) ?? all.shuffled()
        if shuffled.count < 3 {
            shuffled = all.shuffled()
        }
        var idx = d.integer(forKey: indexKey)
        let n = shuffled.count

        func slice(from start: Int, count: Int) -> [String] {
            guard n > 0 else { return [] }
            return (0..<count).map { shuffled[(start + $0) % n] }
        }

        let needsReshuffle = (idx + 3) >= n
        let picks = slice(from: idx % n, count: 3)

        // Advance index and potentially reshuffle for the next call
        if needsReshuffle {
            shuffled = all.shuffled()
            d.set(shuffled, forKey: shuffledKey)
            idx = 0
        } else {
            idx = (idx + 3) % n
        }
        d.set(idx, forKey: indexKey)
        if d.stringArray(forKey: shuffledKey) == nil { d.set(shuffled, forKey: shuffledKey) }
        
        return picks
    }
}
