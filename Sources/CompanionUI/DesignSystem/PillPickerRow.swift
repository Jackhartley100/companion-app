import SwiftUI

/// One preference, shown as a tappable pill with the current value and a menu
/// of alternatives — the app's standard replacement for a plain system list
/// `Picker` wherever a form needs one.
public struct PillPickerRow<Value: CaseIterable & Hashable & Identifiable>: View
where Value.AllCases: RandomAccessCollection {
    let title: String
    @Binding var selection: Value
    let displayName: (Value) -> String

    public init(title: String, selection: Binding<Value>, displayName: @escaping (Value) -> String) {
        self.title = title
        self._selection = selection
        self.displayName = displayName
    }

    public var body: some View {
        Menu {
            ForEach(Value.allCases) { option in
                Button(displayName(option)) { selection = option }
            }
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Colour.primaryText)
                Spacer(minLength: 0)
                HStack(spacing: Theme.Space.xxs) {
                    Text(displayName(selection))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(Theme.Colour.secondaryText)
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity)
            .background(Theme.Colour.surface)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
