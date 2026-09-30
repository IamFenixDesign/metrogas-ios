import WidgetKit
import SwiftUI

@main
struct MetrogasWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LatestInvoiceWidget()
        InvoiceListWidget()
    }
}
