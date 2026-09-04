# Trend relationships and highlights

Trends exposes **Explore relationships** even while the primary baseline is sparse.

- **Signals** compares shedding, scalp severity, oiliness, or reported side-effect severity with manual lifestyle logs, synced Apple Health values, or any recorded plan item. Stopped items remain selectable. Side effects can be filtered by type.
- **Around a change** compares observations in 14-, 28-, or 56-day windows before and after a plan addition/stop, completed procedure, photo, progress check-in, side-effect report, life event, or daily note. The event day belongs to the after window. Each side needs five recorded days before displaying a mean; counts and raw observations remain visible below that threshold.
- **Highlights** lists the dated source records and adds them to the main journey chart. Photo highlights open the source photo; other highlights open the date comparison. Users can filter and expand the list.
- **Baby hairs noticed** is an explicit user observation on photo capture and photo detail. It is stored as `PhotoRecord.babyHairsNoticed` with an inline `false` default. It travels through `PhotoRepository` and full backup/restore; older backups omit it and restore as false. Monthly progress check-ins with reported regrowth also produce highlights. Free text and image contents are never parsed to infer regrowth.

## Data boundaries

`TrendContext` derives highlights, daily side-effect peaks, recorded dose counts, calendar-aligned context, and before/after windows. Duplicate daily entries receive one day's weight. Future records are excluded. Unlogged side effects and doses remain unknown; an explicit missed-dose record can contribute zero logged doses. Repeated named dose slots are counted once per day.

Lag shifts context forward by calendar days, including across DST. The signal graph and association use that same alignment and require exact matching calendar days. Context is loaded from before the visible window when a lag needs it. Association keeps the existing rank-correlation and minimum-data gates. Comparisons describe observed levels and timing without treatment-efficacy or causal claims.

SwiftData remains the source of truth. No server protocol, entitlement, prompt, or attachment changes are involved.
