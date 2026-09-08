import SwiftUI

struct GarageScreen: View {
    var onSaved: (() -> Void)? = nil
    @State private var vehicles: [Vehicle] = []
    @State private var make = ""
    @State private var model = ""
    @State private var year = ""
    @State private var color = "#111111"
    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) { Eyebrow("Garage"); Headline("Your cars", size: 28) }
                    Spacer()
                    Button("+ Add") { adding = true }.font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(HazaTheme.hair, lineWidth: 1))
                }.padding(.top, 8)
                Text("Friends see your primary car next to your name on the map.").font(.system(size: 14)).foregroundStyle(HazaTheme.muted)
                Rectangle().fill(HazaTheme.hair).frame(height: 1)
                ForEach(vehicles) { v in
                    Row(title: v.title, subtitle: v.isPrimary ? "Primary · shown to friends" : "In the garage") {
                        Circle().fill(Color(hex: v.colorHex ?? "#888888")).frame(width: 34, height: 34).overlay(Circle().stroke(HazaTheme.hair, lineWidth: 1))
                    } trailing: { if v.isPrimary { Pill(text: "Primary") } }
                }
                if adding || vehicles.isEmpty {
                    Card {
                        VStack(spacing: 10) {
                            TextField("Make (Ford)", text: $make)
                            TextField("Model (Mustang GT)", text: $model)
                            TextField("Year", text: $year).keyboardType(.numberPad)
                            TextField("Color (#hex)", text: $color)
                            PrimaryButton(title: "Save car") { save() }.disabled(make.isEmpty || model.isEmpty)
                        }.textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
        .background(HazaTheme.bg)
        .task { await load() }
    }

    private func load() async {
        vehicles = (try? await SupabaseService.shared.vehicles()) ?? []
        LocationService.shared.primaryVehicleID = vehicles.first { $0.isPrimary }?.id ?? vehicles.first?.id
    }

    private func save() {
        Task {
            try? await SupabaseService.shared.addVehicle(make: make, model: model, year: Int(year), colorHex: color.hasPrefix("#") && color.count == 7 ? color : nil, primary: vehicles.isEmpty)
            make = ""; model = ""; year = ""; adding = false
            await load(); onSaved?()
        }
    }
}

extension Color {
    init(hex: String) {
        var s = hex; if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0x888888
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
