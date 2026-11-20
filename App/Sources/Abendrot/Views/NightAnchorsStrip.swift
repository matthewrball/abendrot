import SwiftUI
import WarmthKit

// MARK: - NightAnchorsStrip

/// Tonight as one strip: Day → Sunset → Bedtime → Sunrise, noon to noon, with the track painted
/// in the colour the screen will actually be. Sunset and sunrise are the sun's; bedtime is the
/// one anchor that drags. The stepper beside it is the precise path, so this handle is
/// pointer and VoiceOver only.
///
/// Every Kelvin printed is the colour the screen shows at the moment it is printed against.
/// Which ones may be printed is the timeline's rule (`kelvinUnderBedtime`, `lateEaseEnd`), not
/// this view's.
struct NightAnchorsStrip: View {
    let timeline: NightTimeline
    /// The Mac's clock: every time on the strip is read on it, the sun's included.
    let clock: Calendar
    /// Bedtime on the Mac's clock, minutes after midnight.
    let bedtimeMinutes: Int
    let eveningKelvin: Kelvin
    let setBedtime: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isDragging = false
    /// Where the handle sat when the drag began, so it never jumps under the pointer.
    @State private var dragOriginX: CGFloat?

    private let trackHeight: CGFloat = 10
    private let handleSize: CGFloat = 18
    /// Room for "Sunset 10:44 PM". Labels are centred on their anchors in a slot this wide.
    private let labelWidth: CGFloat = 88
    /// The opening anchor has no time to show, so its slot is narrower and sits at the strip's edge.
    private let openingLabelWidth: CGFloat = 64
    private let labelSpacing: CGFloat = 4
    private let labelHeight: CGFloat = 34
    private let labelGap: CGFloat = 9

    private var trackMidY: CGFloat { labelHeight + labelGap + handleSize / 2 }
    private var height: CGFloat { trackMidY + handleSize / 2 + labelGap + labelHeight }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let usable = max(width - handleSize, 1)
            let handleX = x(bedtimeDate, usable)

            ZStack(alignment: .topLeading) {
                track
                    .frame(width: usable, height: trackHeight)
                    .offset(x: handleSize / 2, y: trackMidY - trackHeight / 2)

                ForEach(fixedAnchors(usable)) { anchor in
                    AnchorLabel(kelvin: anchor.kelvin, caption: anchor.caption, kelvinOnTop: true)
                        .frame(width: anchor.labelWidth, height: labelHeight, alignment: .bottom)
                        .offset(x: labelX(anchor.labelCentre, anchor.labelWidth, in: width))
                    Circle()
                        .fill(Theme.Color.inkOnAccent.opacity(0.7))
                        .frame(width: 5, height: 5)
                        .offset(x: anchor.x - 2.5, y: trackMidY - 2.5)
                }
                .accessibilityHidden(true)   // the summary line under the strip says all of this

                // The Kelvin only when the screen really shows the held colour at bedtime. On a
                // late-sunset night the ease ends later, and its own anchor carries the Kelvin.
                AnchorLabel(
                    kelvin: timeline.kelvinUnderBedtime,
                    caption: "Bedtime \(NightClock.text(bedtimeDate, on: clock))",
                    kelvinOnTop: false,
                    emphasized: true
                )
                .frame(height: labelHeight, alignment: .top)
                // Placed by its real width: the semibold "Bedtime 11:30 PM" is wider than the
                // fixed slot the sun's labels use, and would hang over the strip's edge.
                .alignmentGuide(.leading) { label in -labelX(handleX, label.width, in: width) }
                .offset(y: trackMidY + handleSize / 2 + labelGap)
                .accessibilityHidden(true)

                handle
                    .offset(x: handleX - handleSize / 2, y: trackMidY - handleSize / 2)
                    .gesture(drag(handleX: handleX, usable: usable))
            }
            .animation(isDragging ? nil : Theme.Motion.warm(reduceMotion: reduceMotion), value: bedtimeMinutes)
        }
        .frame(height: height)
    }

    // MARK: Track

    /// Each sample is the white point the screen shows at that moment, laid over the cream ground.
    private var track: some View {
        let last = max(timeline.samples.count - 1, 1)
        let stops = timeline.samples.enumerated().map { index, kelvin -> Gradient.Stop in
            let gain = rgbGain(for: kelvin)
            return .init(
                color: Color(.sRGB, red: gain.red, green: gain.green, blue: gain.blue, opacity: 1),
                location: CGFloat(index) / CGFloat(last)
            )
        }
        return Capsule(style: .continuous)
            .fill(Theme.Color.textCream)
            .overlay(
                Capsule(style: .continuous)
                    .fill(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
                    .blendMode(.multiply)
            )
            .compositingGroup()
            .overlay(Capsule(style: .continuous).strokeBorder(.black.opacity(0.3), lineWidth: 0.5))
    }

    // MARK: Bedtime handle

    private var handle: some View {
        Circle()
            .fill(Theme.Gradient.sunset)
            .overlay(Circle().strokeBorder(Theme.Color.textCream.opacity(0.9), lineWidth: 2))
            .shadow(color: Theme.Color.accent.opacity(0.5), radius: 7)
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            .frame(width: handleSize, height: handleSize)
            .scaleEffect(isDragging ? 1.12 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.86), value: isDragging)
            // A bigger target than the 18pt dot, without moving it.
            .padding(9)
            .contentShape(Circle())
            .padding(-9)
            .help("Drag to set your bedtime")
            // A drag the system cancels never reaches `onEnded`; the gesture state still resets.
            .onChange(of: isDragging) { dragging in
                if !dragging { dragOriginX = nil }
            }
            .accessibilityElement()
            .accessibilityLabel("Bedtime")
            .accessibilityValue(NightClock.text(bedtimeDate, on: clock))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: setBedtime(eveningMinutes + AppModel.bedtimeStep)
                case .decrement: setBedtime(eveningMinutes - AppModel.bedtimeStep)
                default: break
                }
            }
    }

    private func drag(handleX: CGFloat, usable: CGFloat) -> some Gesture {
        // Global space: the handle moves under the pointer, and the translation must not move with it.
        // A click that does not move is not a drag, and must not write a bedtime.
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                let origin = dragOriginX ?? handleX
                if dragOriginX == nil { dragOriginX = origin }
                let fraction = Double((origin + value.translation.width - handleSize / 2) / usable)
                // Past either end of the range the handle stays at that end; the timeline knows
                // where the range lies on this night.
                setBedtime(timeline.bedtimeMinutes(
                    at: fraction, in: AppModel.bedtimeRange, step: AppModel.bedtimeStep, calendar: clock
                ))
            }
            .onEnded { _ in dragOriginX = nil }
    }

    // MARK: Geometry

    private var eveningMinutes: Int {
        bedtimeMinutes < 12 * 60 ? bedtimeMinutes + 1440 : bedtimeMinutes
    }

    /// The instant in this night when the Mac's clock reads the bedtime.
    private var bedtimeDate: Date {
        if let bedtime = timeline.bedtime { return bedtime }
        let time = DateComponents(hour: bedtimeMinutes / 60, minute: bedtimeMinutes % 60)
        return clock.nextDate(after: timeline.start, matching: time, matchingPolicy: .nextTime)
            ?? timeline.start
    }

    private func x(_ date: Date, _ usable: CGFloat) -> CGFloat {
        let span = timeline.end.timeIntervalSince(timeline.start)
        let fraction = min(1, max(0, date.timeIntervalSince(timeline.start) / span))
        return handleSize / 2 + CGFloat(fraction) * usable
    }

    /// A label slot's leading edge: centred on its anchor, kept inside the strip. Pure math, so
    /// nonisolated: SwiftUI calls alignment guides outside the main actor.
    nonisolated private func labelX(_ anchorX: CGFloat, _ labelWidth: CGFloat, in width: CGFloat) -> CGFloat {
        min(max(anchorX - labelWidth / 2, 0), max(width - labelWidth, 0))
    }

    // MARK: Fixed anchors

    private struct Anchor: Identifiable {
        let id: String
        let x: CGFloat
        /// Nil where the anchor marks a moment the screen is still on its way somewhere.
        let kelvin: Kelvin?
        let caption: String
        let labelWidth: CGFloat
        /// Where the label is centred. The anchor's own `x`, unless a close neighbour pushed it.
        var labelCentre: CGFloat
    }

    /// What the night opens from, then Sunset and Sunrise where the sun provides them, and the
    /// end of the ease on a night when that falls after bedtime. The opening anchor marks no
    /// moment, so it sits at the strip's edge; it gives way when an early sunset needs the room,
    /// and Sunrise gives way on a night too short to fit the labels.
    private func fixedAnchors(_ usable: CGFloat) -> [Anchor] {
        func opening(_ kelvin: Kelvin, _ caption: String) -> Anchor {
            Anchor(id: "opening", x: openingLabelWidth / 2, kelvin: kelvin, caption: caption,
                   labelWidth: openingLabelWidth, labelCentre: openingLabelWidth / 2)
        }
        func easeEnd(_ end: NightTimeline.Mark) -> Anchor {
            let endX = x(end.date, usable)
            return Anchor(
                id: "ease-end", x: endX, kelvin: end.kelvin,
                caption: "Eased \(NightClock.text(end.date, on: clock))", labelWidth: labelWidth, labelCentre: endX
            )
        }
        let day = opening(.neutral, "Day")
        guard let sunset = timeline.sunset else { return [day] }
        // The sun is already down at noon: there is no day, and no sunset to mark.
        guard sunset > timeline.start else {
            var anchors = [opening(eveningKelvin, "Polar night")]
            if let end = timeline.lateEaseEnd,
               x(end.date, usable) - openingLabelWidth / 2 >= (labelWidth + openingLabelWidth) / 2 + labelSpacing {
                anchors.append(easeEnd(end))
            }
            return anchors
        }

        let sunsetX = x(sunset, usable)
        var sunsetAnchor = Anchor(
            id: "sunset", x: sunsetX, kelvin: eveningKelvin,
            caption: "Sunset \(NightClock.text(sunset, on: clock))", labelWidth: labelWidth, labelCentre: sunsetX
        )
        var endAnchor = timeline.lateEaseEnd.map(easeEnd)
        if var end = endAnchor, end.x - sunsetX < labelWidth + labelSpacing {
            // The ease ends at most two hours after sunset, too close for two labels: they part
            // around the midpoint of their two dots, and stay inside the strip together.
            let fullWidth = usable + handleSize
            let pairWidth = 2 * labelWidth + labelSpacing
            let leading = min(max((sunsetX + end.x) / 2 - pairWidth / 2, 0), max(fullWidth - pairWidth, 0))
            sunsetAnchor.labelCentre = leading + labelWidth / 2
            end.labelCentre = leading + labelWidth + labelSpacing + labelWidth / 2
            endAnchor = end
        }

        var anchors: [Anchor] = []
        if sunsetAnchor.labelCentre - day.x >= (labelWidth + openingLabelWidth) / 2 + labelSpacing {
            anchors.append(day)
        }
        anchors.append(sunsetAnchor)
        if let endAnchor { anchors.append(endAnchor) }
        let lastCentre = endAnchor?.labelCentre ?? sunsetAnchor.labelCentre
        if let sunrise = timeline.sunrise, x(sunrise, usable) - lastCentre >= labelWidth + labelSpacing {
            // The night is still held at sunrise; day returns over the ease that follows it.
            anchors.append(Anchor(
                id: "sunrise", x: x(sunrise, usable), kelvin: nil,
                caption: "Sunrise \(NightClock.text(sunrise, on: clock))", labelWidth: labelWidth,
                labelCentre: x(sunrise, usable)
            ))
        }
        return anchors
    }
}

// MARK: - NightClock

/// Short clock times in the user's own 12/24-hour style.
enum NightClock {
    static func text(_ date: Date, on clock: Calendar) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = clock.timeZone
        return date.formatted(style)
    }

    /// A time of day given as minutes after midnight.
    static func text(minutes: Int) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return text(Date(timeIntervalSinceReferenceDate: TimeInterval(minutes % 1440) * 60), on: utc)
    }
}

// MARK: - AnchorLabel

/// An anchor's two lines: the Kelvin it marks and what it is. The caption sits nearest the track.
private struct AnchorLabel: View {
    let kelvin: Kelvin?
    let caption: String
    let kelvinOnTop: Bool
    var emphasized = false

    var body: some View {
        VStack(spacing: 3) {
            if kelvinOnTop { kelvinText }
            Text(caption)
                .font(Theme.Typography.ui(10.5, weight: emphasized ? .semibold : .regular))
                .foregroundStyle(emphasized ? Theme.Color.accentText : Theme.Color.textMuted)
            if !kelvinOnTop { kelvinText }
        }
        .lineLimit(1)
        .fixedSize()
    }

    @ViewBuilder private var kelvinText: some View {
        if let kelvin { KelvinReadout(kelvin: kelvin, size: 15) }
    }
}

// MARK: - KelvinReadout

/// A small Kelvin value in the readout's own serif, the way the big warmth ticker sets it.
struct KelvinReadout: View {
    let kelvin: Kelvin
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(kelvin.displayValue.formatted(.number))
                .font(Theme.Typography.serif(size))
                .monospacedDigit()
                .foregroundStyle(Theme.Color.textPrimary)
            Text("K")
                .font(Theme.Typography.serif(size * 2 / 3))
                .foregroundStyle(Theme.Color.accentText)
        }
        .accessibilityElement()
        .accessibilityLabel("\(kelvin.displayValue) Kelvin")
    }
}
