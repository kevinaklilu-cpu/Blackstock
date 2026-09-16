from pathlib import Path

repo = Path.cwd()
path = repo / "Sources/Blackstock/AppStore+Guidance.swift"
text = path.read_text()

old = '''    let ranked = TopicTaxonomy.stableCategories
      .map { category -> (TopicCategory, Int) in
        let hits = category.searchTerms.reduce(0) { partial, term in
          let needle = term.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
          return partial + folded.components(separatedBy: needle).count - 1
        }
        return (category, hits)
      }
      .filter { $0.1 > 0 }
      .sorted { lhs, rhs in lhs.1 == rhs.1 ? lhs.0.rawValue < rhs.0.rawValue : lhs.1 > rhs.1 }
'''

new = '''    var scoredCategories: [(TopicCategory, Int)] = []
    for category in TopicTaxonomy.stableCategories {
      var hits = 0
      for term in category.searchTerms {
        let needle = term.folding(
          options: [.diacriticInsensitive, .caseInsensitive],
          locale: .current)
        let occurrences = folded.components(separatedBy: needle).count - 1
        hits += occurrences
      }
      if hits > 0 {
        scoredCategories.append((category, hits))
      }
    }
    let ranked = scoredCategories.sorted { lhs, rhs in
      if lhs.1 == rhs.1 {
        return lhs.0.rawValue < rhs.0.rawValue
      }
      return lhs.1 > rhs.1
    }
'''

if new in text:
    print("BLACKSTOCK_SWIFT63_GUIDANCE_HOTFIX_ALREADY_APPLIED")
elif old in text:
    path.write_text(text.replace(old, new, 1))
    print("BLACKSTOCK_SWIFT63_GUIDANCE_HOTFIX_OK")
else:
    raise SystemExit("Expected channel identity ranking expression not found")
