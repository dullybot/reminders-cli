import Foundation
@testable import RemindersLibrary
import Testing

struct SortTests {
    private let earlier = Date(timeIntervalSince1970: 0)
    private let later = Date(timeIntervalSince1970: 100)

    @Test func ascending() {
        #expect(CustomSortOrder.ascending.isOrdered(earlier, later))
        #expect(!CustomSortOrder.ascending.isOrdered(later, earlier))
    }

    @Test func descending() {
        #expect(CustomSortOrder.descending.isOrdered(later, earlier))
        #expect(!CustomSortOrder.descending.isOrdered(earlier, later))
    }

    @Test(arguments: CustomSortOrder.allCases)
    func missingDatesSortLast(order: CustomSortOrder) {
        #expect(order.isOrdered(earlier, nil))
        #expect(!order.isOrdered(nil, earlier))
        #expect(!order.isOrdered(nil, nil))
    }
}
