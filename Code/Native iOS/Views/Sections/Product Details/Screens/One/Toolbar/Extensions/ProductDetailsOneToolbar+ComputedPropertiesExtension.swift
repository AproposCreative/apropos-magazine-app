//
//  ProductDetailsOneToolbar+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension ProductDetailsOneToolbarView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the storage options of the product should be shown at all:
    var isShowingStorages: Bool {
        !storages.isEmpty
    }
    
    /// 'Bool' value indicating whether or not the 'Buy' button should be disabled:
    var isBuyDisabled: Bool {
        selectedStorage == nil
    }
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// An array of the storage options of the product to display:
    var storages: [NT_ProductStorage] {
        product.storages
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
}
