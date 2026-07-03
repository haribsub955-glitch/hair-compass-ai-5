# Handoff: Mobile Redesign (Today / Trends / Plan / Labs / Photos)

## Why "confirmed but nothing changed" happens

I re-read the actual Swift files in your attached repo just now (`TodayView.swift`,
`PhotosView.swift`, `LabsView.swift`, `CareView.swift`) — **none of them contain any of the
redesign changes**. Claude Code's "incorporated" confirmation was not reflected in the files on
disk, which is why the simulator looked untouched. In order of likelihood:

1. **Wrong working directory / repo.** If Claude Code was run from a different folder than the
   one Xcode has open (or a stale git worktree/clone), it can edit files that Xcode never sees.
   Check `git status` / `git diff` immediately after it says "done" — if it shows nothing, the
   edit didn't land where you think.
2. **Simulator ran a cached build.** Xcode sometimes reuses a build if it doesn't detect a file
   change (rare, but happens with SwiftUI preview caches). Force it: **Product → Clean Build
   Folder (⇧⌘K)**, then stop the app, quit Simulator entirely, and re-run.
3. **Target membership.** If any new file was created (rather than an existing one edited), check
   it's added to the **Hair Compass AI 5** target in the file inspector — a file with no target
   membership compiles into nothing.
4. **It edited a preview/mock, not the live view.** Confirm the class Xcode is actually showing is
   `TodayView` / `CareView` / etc. in `Feature/` — not a copy, a `#Preview` block, or a SwiftUI
   preview provider.
5. **Ambiguous instructions.** Vague prompts like "make it match the new design" give Claude Code
   room to make a small, safe change (or none) and still say "incorporated." The rewrite below is
   literal, file-by-file, so there's nothing to interpret.

**Recommended next step:** paste one section of this doc at a time into Claude Code (start with
Today), and immediately after it replies, run `git diff Feature/TodayView.swift` yourself before
building — confirm the diff exists before touching Xcode at all.

---

## Fidelity

High-fidelity. The HTML prototype (`Hair Compass Redesign v2.dc.html`, open it in a browser to
interact with it) is pixel-accurate for color, spacing, and copy. The Swift below is a direct,
compilable-style translation using your existing `Clinical` design system — no new tokens, no new
dependencies. Treat it as literal code to paste in and adapt to your exact model property names
(I've used the ones visible in your current files; double check `DailyEntry`, `Treatment`,
`LabResult`, `PhotoRecord` field names still match).

---

## 1. Today — merged hero + header, single routine card

**File:** `Feature/TodayView.swift`

Replace `header` and `heroBanner` with one hero block that the greeting sits inside (not above):

```swift
private var heroHeader: some View {
    ZStack(alignment: .bottomLeading) {
        Image(BrandArt.todayHero)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(height: 224)
            .frame(maxWidth: .infinity)
            .clipped()
        LinearGradient(
            colors: [Clinical.canvas.opacity(0.06), Clinical.canvas.opacity(0.72), Clinical.canvas],
            startPoint: .top, endPoint: .bottom
        )
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()).uppercased())
                    .font(Clinical.eyebrow(10)).tracking(1.4).foregroundStyle(Clinical.secondary)
                Text(greeting).font(Clinical.headline(31)).foregroundStyle(Clinical.ink)
            }
            Spacer()
            Label("\(streak)-day streak", systemImage: "flame.fill")
                .font(Clinical.eyebrow(10))
                .foregroundStyle(Clinical.accent)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Clinical.surface.opacity(0.85), in: Capsule())
                .overlay(Capsule().strokeBorder(Clinical.hairline, lineWidth: 1))
        }
        .padding(.horizontal, 20).padding(.bottom, 10)
    }
    .frame(height: 224)
    .clipShape(RoundedRectangle(cornerRadius: 0)) // full-bleed — no card radius at the very top
}
```

In `body`, replace:
```swift
header
heroBanner
logCard
```
with:
```swift
heroHeader
    .padding(.horizontal, -20) // cancel the outer ScrollView's 20pt padding so it bleeds edge-to-edge
logCard
```
(Since the outer `VStack` has `.padding(.horizontal, 20)`, the simplest fix is actually to pull
`heroHeader` **outside** the padded `VStack` — put it directly in the `ScrollView` before the
`VStack` starts, sized to full width, and start the `VStack`'s horizontal padding only below it.)

Merge `treatmentsCard` into `logCard`'s layout so Today shows one combined card (log stats + routine
checklist) rather than two separate cards — reuse the existing `treatmentRow` exactly as written,
just move it inside `logCard`'s `VStack` when `activeDaily` is non-empty.

Drop `readoutCard` and `baselineCard` from the Today scroll (keep the source — just don't call them
in `body`) — the redesign consolidates that into Plan/profile to reduce duplication.

---

## 2. Plan — coach card with a progress ring

**File:** `Feature/CareView.swift`

Replace the `coachCard`'s body with a ring on the trailing side:

```swift
private var coachCard: some View {
    let msg = AdherenceCoach.message(doneToday: doneToday, totalToday: dailySteps.count, streak: streak, weeklyAdherence: nil)
    let progress = dailySteps.isEmpty ? 0 : Double(doneToday) / Double(dailySteps.count)
    return ClinicalCard {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Coach")
                Text(msg.headline).font(Clinical.headline(21)).foregroundStyle(Clinical.ink)
                Text(msg.detail).font(.system(size: 13)).foregroundStyle(Clinical.secondary)
            }
            Spacer(minLength: 8)
            ZStack {
                Circle().stroke(Clinical.hairline, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Clinical.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(doneToday)").font(Clinical.headline(17))
                    Text("OF \(dailySteps.count)").font(Clinical.eyebrow(8)).foregroundStyle(Clinical.tertiary)
                }
            }
            .frame(width: 60, height: 60)
        }
    }
}
```

---

## 3. Labs — reference-range gauge per result

**File:** `Feature/LabsView.swift`

Replace `labRow(_:)`'s inner content with a gauge under the existing header row:

```swift
private func labRow(_ lab: LabResult) -> some View {
    let lo = lab.test.referenceRange.lowerBound
    let hi = lab.test.referenceRange.upperBound
    let domainLo = lo * 0
    let domainHi = hi * 1.1
    let pct = min(1, max(0, (lab.value - domainLo) / (domainHi - domainLo)))
    let bandStart = (lo - domainLo) / (domainHi - domainLo)
    let bandWidth = (hi - lo) / (domainHi - domainLo)

    return ClinicalCard {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lab.test.title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(Clinical.ink)
                    Text(lab.collectedAt.formatted(.dateTime.month().day().year()))
                        .font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(lab.value.formatted(.number.precision(.fractionLength(0...1)))) \(lab.test.unit)")
                        .font(Clinical.number(17)).foregroundStyle(Clinical.ink)
                    Text(lab.flag.title).font(Clinical.eyebrow(9)).foregroundStyle(Clinical.flagColor(lab.flag))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Clinical.hairline.opacity(0.5)).frame(height: 6)
                    Capsule().fill(Clinical.positive.opacity(0.22))
                        .frame(width: geo.size.width * bandWidth, height: 6)
                        .offset(x: geo.size.width * bandStart)
                    Circle().fill(Clinical.flagColor(lab.flag))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Clinical.surface, lineWidth: 2.5))
                        .offset(x: geo.size.width * pct - 7, y: -4)
                }
            }
            .frame(height: 14)
            HStack {
                Text("\(Int(domainLo))").font(Clinical.number(8.5)).foregroundStyle(Clinical.tertiary)
                Spacer()
                Text("RANGE \(Int(lo))–\(Int(hi))").font(Clinical.eyebrow(8.5)).foregroundStyle(Clinical.secondary)
                Spacer()
                Text("\(Int(domainHi))").font(Clinical.number(8.5)).foregroundStyle(Clinical.tertiary)
            }
        }
    }
    .contextMenu { Button("Delete", role: .destructive) { context.delete(lab) } }
}
```

---

## 4. Photos — draggable before/after compare slider

**File:** `Feature/PhotosView.swift`

Replace `compareCard` with a draggable slider (this needs a small `@State` var, add
`@State private var comparePosition: CGFloat = 0.5` to `PhotosView`):

```swift
private var compareCard: some View {
    let first = regionPhotos.first!
    let last = regionPhotos.last!
    return ClinicalCard {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "First vs latest")
                Spacer()
                Text("DRAG TO COMPARE").font(Clinical.eyebrow(9)).foregroundStyle(Clinical.accent)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    thumbImage(last).frame(width: geo.size.width, height: 260)
                    thumbImage(first)
                        .frame(width: geo.size.width, height: 260)
                        .mask(Rectangle().frame(width: geo.size.width * comparePosition))
                    Rectangle()
                        .fill(Clinical.surface)
                        .frame(width: 2)
                        .offset(x: geo.size.width * comparePosition - 1)
                        .shadow(radius: 3)
                    Circle()
                        .fill(Clinical.surface)
                        .frame(width: 34, height: 34)
                        .shadow(radius: 3)
                        .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Clinical.accent))
                        .position(x: geo.size.width * comparePosition, y: 130)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .gesture(
                    DragGesture().onChanged { v in
                        comparePosition = min(1, max(0, v.location.x / geo.size.width))
                    }
                )
            }
            .frame(height: 260)
        }
    }
}

private func thumbImage(_ record: PhotoRecord) -> some View {
    Group {
        if let image = PhotoStore.shared.load(record.imagePath) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Clinical.canvas
        }
    }
    .clipped()
}
```

---

## Design tokens (unchanged, reference only)

Canvas `#FBF6EF` · Surface `#FEFCF9` · Ink `#2B211A` · Secondary `#7A6B5D` · Tertiary `#A69687` ·
Hairline `#EDE1D3` · Accent `#B1592E` · Gold `#C9A15A` · Sage `#8A9D7B` ·
Positive/Warning/Critical `#5C7A52` / `#B98B2E` / `#A6432E`. Card radius 22pt, shadow
`Clinical.cardShadow` (warm espresso, not gray).

## Files in this bundle

- `README.md` — this document
- `Hair Compass Redesign v2.dc.html` — interactive reference prototype, open in any browser

The HTML file is a **design reference**, not code to ship — recreate it in SwiftUI using the
snippets above, adapted to your exact model property names.
