import Foundation

struct AccountProfile: Hashable, Codable {
    var holderName: String
    var customerNumber: String
    var supplyAddress: String
    var locality: String
    var postalCode: String
    var email: String
    var phone: String
    var meterNumber: String
    var tariffCategory: String
}
