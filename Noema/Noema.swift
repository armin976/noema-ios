// Noema.swift
//  Noema – iPhone‑first local‑LLM chat (verbose console logging)
//
//  This file now intentionally keeps only the lightweight glue that ties the
//  application entry point together. All heavy view models, helpers, and
//  download/tooling logic live in App/AppGlue.swift after the A2b2a refactor.
//
//  Requires Swift Concurrency (iOS 17+).

import SwiftUI

@_exported import Foundation

// The main app entry lives in App/AppEntry.swift. This file exists as a
// convenient place for future app-wide wiring without pulling in the full
// implementation details that previously lived here.
