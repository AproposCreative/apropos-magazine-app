//
//  NT_TransactionAttachment.swift
//  Native
//

import Foundation

struct NT_TransactionAttachment {
    
    // MARK: - Properties:
    
    /// Identifier of the attachment:
    let id: String
    
    /// An actual content of the attachment
    let content: Data?
    
    init(
        id: String,
        content: Data?
    ) {
        
        /// Properties initialization:
        self.id = id
        self.content = content
    }
}

// MARK: - Identifiable:

extension NT_TransactionAttachment: Identifiable {  }

// MARK: - Equatable:

extension NT_TransactionAttachment: Equatable {  }

// MARK: - Hashable:

extension NT_TransactionAttachment: Hashable {  }
