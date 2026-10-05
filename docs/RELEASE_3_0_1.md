# Blackstock 3.0.1 · Build 301

Discovery now uses its own category selection, defaulting to all categories instead of silently inheriting the channel's category. Explicit discovery categories apply to typed searches too. The selected period and format stay strict. Failed trend-chart requests no longer prevent ordinary search. A search failure alongside usable trend results is visible rather than appearing to be the end of the feed.

Pagination counts distinct new videos, scans up to four provider pages per action, retains the continuation cursor, detects cursor cycles and preserves partial successes. Unsubmitted search text no longer disables loading the currently displayed feed. Additional pages append without jumping existing rows. The list includes its own footer and load-more control. Seven new regressions cover sparse first pages, duplicates, empty filtered pages, cycles, 400 results and speech chunk boundaries.

Long-form speech recognition uses short overlapping requests, projects timestamps back to the source, preserves sentence punctuation and reports percentage progress. Completed source transcripts are reused when choosing another format. Recognition has a timeout and project-switch protection. Clip selection preserves the optional caption choice. Manual framing affects only the current clip; selecting another unframed clip computes its own focus.

References: YouTube pagination https://developers.google.com/youtube/v3/guides/implementation/pagination and search parameters https://developers.google.com/youtube/v3/docs/search/list . The app cannot guarantee a particular live result count or bypass API quota limits.

Build 206 was still installed in /Applications when this work started. Build 301 is a new installer, not an automatic update. Without Developer ID signing, macOS may require Google reauthentication after changing builds. Live channel tests depend on that authentication; automated synthetic upload tests do not constitute an actual upload.
