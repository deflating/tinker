# Seed Configurator — UX Spec

## Overview

A guided wizard that replaces the raw markdown editor for first-time seed setup. Lives alongside the existing `SettingsConfiguratorView` — users can always switch to the raw editor. Think macOS Setup Assistant: friendly, linear, skippable.

## Architecture

### Entry Point

Add a `GuidedConfiguratorView` that the app shows when seeds are empty (first launch) or when the user clicks "Setup Guide" from the existing settings page.

### Navigation Structure

```
┌─────────────────────────────────────────────────┐
│  [sidebar]          │  [main content]           │
│                     │                           │
│  ● About You        │  Form fields for the      │
│  ○ Your Agent       │  currently selected step   │
│  ○ Relationship     │                           │
│  ○ Current Context  │                           │
│  ○ Review & Save    │                           │
│                     │                           │
│                     │  [Back]  [Skip]  [Next →] │
└─────────────────────────────────────────────────┘
```

Sidebar shows all steps with status indicators:
- `●` filled circle = current step
- `◐` half circle = partially filled
- `○` empty circle = not started
- `✓` checkmark = complete

Users can click any step to jump to it. Linear flow is suggested, not enforced.

---

## Step 1: About You (`user.md`)

**Intro text:** *"Help your AI understand who you are — not your resume, but how you actually think and work."*

### Section: Identity
| Field | Component | Maps to |
|-------|-----------|---------|
| Name | `TextField` | `{{USER_NAME}}` |
| What you do | `TextField` (placeholder: "iOS dev, writer, researcher...") | `{{ROLE_AND_DOMAIN}}` |
| Timezone | `Picker` (system timezones, auto-detect default) | `{{TIMEZONE}}` |

### Section: How You Think
| Field | Component | Maps to |
|-------|-----------|---------|
| Problem-solving style | `Picker` with 4 options: "Start broad, then narrow" / "Dive into details first" / "Think out loud" / "Need quiet processing time" | `Problem-solving approach` |
| When stuck, you... | `Picker`: "Step away" / "Push harder" / "Ask someone" / "Reframe the problem" | `When stuck` |
| How you reason | Multi-select chips: "Systems thinking" / "First principles" / "Analogies" / "Visual/spatial" / custom text field | `Mental models` |

### Section: What You Care About
| Field | Component | Maps to |
|-------|-----------|---------|
| Main objectives | 2x `TextField` (add more button, max 4) | `Primary objectives` |
| What "good work" means | `Picker`: "Elegant code" / "Ship fast" / "Deep correctness" / "Creative expression" + custom | `What good work means` |

### Section: Communication
| Field | Component | Maps to |
|-------|-----------|---------|
| How you like to talk | `Picker`: "Casual and direct" / "Technically precise" / "Warm but efficient" | `Preferred register` |
| How much explanation | `Segmented control` (3): "Just the answer" / "Brief rationale" / "Full reasoning" | `How much explained` |
| How you give feedback | `Picker`: "Blunt and fast" / "Diplomatic" / "Questions over statements" | `How they give feedback` |
| Bad news delivery | `Picker`: "Straight" / "Softened with options" / "Framed as tradeoffs" | `Bad news preference` |

### Section: Frustrations & Preferences
| Field | Component | Maps to |
|-------|-----------|---------|
| Things that annoy you | 2x `TextField` (placeholder examples from template) + add more | `What Frustrates Them` |
| Things you don't want | 2x `TextField` | `Things They Don't Want` |
| Your strengths | 2x `TextField` | `Strengths to Lean On` |
| Current constraints | 2x `TextField` (e.g., "limited time", "new to Swift") | `Constraints` |

### Section: Environment
| Field | Component | Maps to |
|-------|-----------|---------|
| OS | `Picker` auto-detected: macOS / Linux / Windows | `OS` |
| Languages | Tag input (chips): type + enter to add | `Primary languages` |
| Key tools | Tag input (chips) | `Key tools` |

---

## Step 2: Your Agent (`agent.md`)

**Intro text:** *"Build your AI's personality. This shapes how it talks, thinks, and makes decisions."*

### Section: Role
| Field | Component | Maps to |
|-------|-----------|---------|
| Role description | `TextEditor` (3 lines, placeholder from template) | `{{ROLE_DESCRIPTION}}` |

### Section: Voice
| Field | Component | Maps to |
|-------|-----------|---------|
| Sounds like... | `Picker`: "Sharp colleague who respects your time" / "Patient mentor who thinks out loud" / "Direct co-founder who challenges ideas" + custom | `You sound like` |
| Default stance | `Picker`: "Opinionated but flexible" / "Neutral until asked" / "Proactively suggestive" | `Default stance` |
| Avoids | Multi-select chips: "Corporate hedging" / "Excessive caveats" / "Unsolicited praise" / "Filler phrases" + custom | `You avoid` |

### Section: Decision-Making
| Field | Component | Maps to |
|-------|-----------|---------|
| When ambiguous | `Picker`: "Best guess and proceed" / "Ask one clarifying question" / "2 options with recommendation" | `When it's ambiguous` |
| When uncertain | Read-only text (always "say so plainly") | — |
| Primary bias | `Segmented control` (4): Simplicity / Robustness / Speed / Correctness | `Bias toward` |

### Section: Principles
| Field | Component | Maps to |
|-------|-----------|---------|
| Core principles | 3x `TextField` (min 1, max 5) with example placeholders rotating | `Your Principles` |

### Section: Code Approach
| Field | Component | Maps to |
|-------|-----------|---------|
| Additional code principle | `TextField` (placeholder: "Tests before implementation", "Minimal dependencies"...) | `{{ADDITIONAL_CODE_PRINCIPLE}}` |

---

## Step 3: Relationship (`self.md`)

**Intro text:** *"This file is special — it's written by your AI over time. Think of it as your AI's working notes about how your collaboration is going. You can seed it with initial observations, or leave it blank and let it build naturally."*

### Section: What Works (optional)
| Field | Component | Maps to |
|-------|-----------|---------|
| Patterns that work | 2x `TextField` (optional, placeholder examples) | `What Works` |

### Section: What Doesn't Work (optional)
| Field | Component | Maps to |
|-------|-----------|---------|
| Patterns to avoid | 2x `TextField` (optional) | `What Doesn't Work` |

### Section: Initial Observations (optional)
| Field | Component | Maps to |
|-------|-----------|---------|
| Anything else to note | `TextEditor` (5 lines, optional) | `How They're Wired` |

**Note below form:** *"After your first few conversations, your AI will start filling this in on its own."*

---

## Step 4: Current Context (`context.md`)

**Intro text:** *"What are you working on right now? This helps your AI pick up where you left off each session."*

### Section: Right Now
| Field | Component | Maps to |
|-------|-----------|---------|
| Current snapshot | `TextEditor` (3 lines, placeholder: "What's the state of things?") | `{{CURRENT_SNAPSHOT}}` |

### Section: Active Threads
Repeating group (1-4), each with:
| Field | Component | Maps to |
|-------|-----------|---------|
| Thread name | `TextField` | `{{THREAD_NAME}}` |
| Status | `Picker`: Active / Blocked / Wrapping Up | `{{STATUS}}` |
| What's happening | `TextEditor` (2 lines) | Description |
| Next step | `TextField` | `Next likely step` |

Button: "+ Add thread" (max 4)

### Section: Energy Level (optional)
| Field | Component | Maps to |
|-------|-----------|---------|
| Bandwidth | `Segmented control` (3): Low / Medium / High | `Bandwidth` |
| Notes | `TextField` (placeholder: "deadline Friday", "exploratory mood") | `Notes` |

---

## Step 5: Review & Save

Shows a summary card for each seed file:
- Title + icon
- Completion percentage (fields filled / total fields)
- "Edit" button to jump back to that step
- Preview of first ~3 lines of generated markdown

**Primary action:** "Save All & Start" button
**Secondary:** "Save & Edit Raw" to switch to the existing markdown editor

---

## Markdown Compilation

Each step compiles its form data into the corresponding template by replacing `{{PLACEHOLDER}}` tokens. Logic:

```
func compileSeed(template: String, values: [String: String]) -> String {
    var result = template
    for (key, value) in values {
        result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
    }
    // Remove unfilled placeholders (optional/skipped fields)
    result = result.replacingOccurrences(of: "\\{\\{.*?\\}\\}", with: "*(not yet set)*", options: .regularExpression)
    return result
}
```

Multi-value fields (objectives, principles, frustrations) compile as markdown list items. Tag inputs compile as comma-separated values.

---

## SwiftUI Implementation Notes

### Data Model
```swift
@Observable
class ConfiguratorState {
    // Step 1 - User
    var userName = ""
    var roleAndDomain = ""
    var timezone = TimeZone.current.identifier
    var problemSolvingStyle = ""
    var whenStuck = ""
    var mentalModels: [String] = []
    var objectives: [String] = ["", ""]
    var goodWorkMeans = ""
    var preferredRegister = ""
    var explanationLevel = ""
    var feedbackStyle = ""
    var badNewsPreference = ""
    var frustrations: [String] = ["", ""]
    var dontWant: [String] = ["", ""]
    var strengths: [String] = ["", ""]
    var constraints: [String] = ["", ""]
    var os = "macOS"
    var languages: [String] = []
    var tools: [String] = []

    // Step 2 - Agent
    var roleDescription = ""
    var soundsLike = ""
    var defaultStance = ""
    var avoids: [String] = []
    var whenAmbiguous = ""
    var biasToward = ""
    var principles: [String] = ["", "", ""]
    var codePrinciple = ""

    // Step 3 - Self
    var whatWorks: [String] = ["", ""]
    var whatDoesntWork: [String] = ["", ""]
    var initialObservations = ""

    // Step 4 - Context
    var currentSnapshot = ""
    var threads: [ThreadEntry] = [ThreadEntry()]
    var bandwidth = "Medium"
    var energyNotes = ""

    var currentStep = 0
}
```

### Key Components to Build

1. **`GuidedConfiguratorView`** — outer shell with sidebar + content area
2. **`ConfiguratorSidebar`** — step list with progress indicators
3. **`UserSeedStep`** — form for step 1
4. **`AgentSeedStep`** — form for step 2
5. **`SelfSeedStep`** — form for step 3
6. **`ContextSeedStep`** — form for step 4
7. **`ReviewStep`** — summary + save
8. **`ChipInput`** — reusable tag/chip input for multi-value fields
9. **`DynamicListField`** — reusable "add another" text field list

### Styling

- Match existing app style: use `FamiliarApp.accent`, `FamiliarApp.earthSand` etc.
- Form sections with `GroupBox` or custom card backgrounds
- Generous spacing — not cramped
- Monospace preview text on Review step to match the editor

### Navigation

- `currentStep` integer drives which view is shown
- Back/Next/Skip buttons in a bottom bar
- Sidebar items are clickable to jump
- "Skip" advances without saving (fields stay empty)
- "Next" auto-saves current step's data to state
- On "Save All", compile all 4 templates and write via `SeedManager`

---

## Scope Boundaries

**In scope:**
- The 5 screens described above
- Compiling form data to markdown templates
- Writing to seed files via existing `SeedManager`
- Entry from first-launch or settings button

**Out of scope (for now):**
- Importing existing seed file data back into form fields
- AI-assisted seed generation ("describe yourself and I'll fill this in")
- Undo/redo within the configurator
- Animations between steps
