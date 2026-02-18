import ActivityKit
import WidgetKit
import SwiftUI

struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
  public typealias LiveDeliveryData = ContentState
  
  public struct ContentState: Codable, Hashable {
    var appGroupId: String
  }
  
  var id = UUID()
}

func getCountdownDate(from appGroupId: String, prefix: UUID) -> Date? {
  guard let defaults = UserDefaults(suiteName: appGroupId),
        let fireAtMs = defaults.object(forKey: "\(prefix)_fireAtEpochMs") as? Int else {
    return nil
  }
  return Date(timeIntervalSince1970: Double(fireAtMs) / 1000)
}

func getCountDownText(from appGroupId: String, prefix: UUID) -> String {
  guard let defaults = UserDefaults(suiteName: appGroupId),
        let text = defaults.string(forKey: "\(prefix)_countDownText"),
        !text.isEmpty else {
    return "TBA"
  }
  return text
}

struct MonkeycraftWidgetLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
      HStack(alignment: .top) {
        Text(getCountDownText(from: context.state.appGroupId, prefix: context.attributes.id))
          .font(.headline)
          .foregroundColor(.primary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer()
        CountdownView(appGroupId: context.state.appGroupId, prefix: context.attributes.id)
          .font(.system(size: 28, weight: .medium, design: .monospaced))
          .foregroundColor(.green)
          .multilineTextAlignment(.trailing)
      }
      .padding()
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.center) {
          HStack(alignment: .top) {
            Text(getCountDownText(from: context.state.appGroupId, prefix: context.attributes.id))
              .font(.headline)
              .foregroundColor(.white)
              .fixedSize(horizontal: false, vertical: true)
            Spacer()
            CountdownView(appGroupId: context.state.appGroupId, prefix: context.attributes.id)
              .font(.system(size: 24, weight: .medium, design: .monospaced))
              .foregroundColor(.green)
          }
        }
      } compactLeading: {
        Text(getCountDownText(from: context.state.appGroupId, prefix: context.attributes.id))
          .font(.caption)
          .foregroundColor(.white)
          .lineLimit(1)
          .truncationMode(.tail)
      } compactTrailing: {
        CountdownView(appGroupId: context.state.appGroupId, prefix: context.attributes.id)
          .font(.system(.body, design: .monospaced))
          .foregroundColor(.green)
      } minimal: {
        CountdownView(appGroupId: context.state.appGroupId, prefix: context.attributes.id)
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(.green)
      }
    }
  }
}

struct CountdownView: View {
  let appGroupId: String
  let prefix: UUID
  
  var body: some View {
    Group {
      if let targetDate = getCountdownDate(from: appGroupId, prefix: prefix) {
        if targetDate > Date() {
          Text(timerInterval: Date()...targetDate)
            .foregroundColor(.green)
        } else {
          Text("00:00")
            .foregroundColor(.gray)
        }
      } else {
        Text("--:--")
          .foregroundColor(.gray)
      }
    }
    .monospacedDigit()
  }
}
