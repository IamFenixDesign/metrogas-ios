import SwiftUI

struct ConsumptionView: View {
    var body: some View {
        NavigationStack {
            MetrogasPortalScreen(title: "Consumo", url: MetrogasURLs.portalMobile)
        }
    }
}

#Preview {
    ConsumptionView()
        .environmentObject(AppSession())
}
