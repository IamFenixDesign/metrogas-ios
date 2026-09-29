import SwiftUI

struct InvoiceListView: View {
    var body: some View {
        NavigationStack {
            MetrogasPortalScreen(title: "Facturas", url: MetrogasURLs.portalMobile)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Image("MetrogasLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 18)
                            .accessibilityHidden(true)
                    }
                }
        }
    }
}

#Preview {
    InvoiceListView()
        .environmentObject(AppSession())
}
