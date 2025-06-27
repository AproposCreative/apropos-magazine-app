//
//  FileEditingThreeBoard+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension FileEditingThreeBoardView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the notes that are part of the board is empty:
    var isNotesEmpty: Bool {
        notes.isEmpty
    }
    
    /// An array of the notes that are part of the board to display:
    var notes: [NT_WhiteboardNote] {
        board.notes
    }
    
    /// Title of the board:
    var title: String {
        board.title
    }
    
    /// Font of the buttons that are displayed on the view:
    var buttonFont: Font {
        .body
    }
    
    /// Symbol variant of the icons of the buttons that are displayed on the view:
    var buttonIconSymbolVariant: SymbolVariants {
        .none
    }
    
    /// Frame of each of the notes:
    var noteFrame: Double {
        200
    }
    
    /// Padding of the notes:
    var notesPadding: Double {
        16
    }
    
    /// Style of the buttons that are displayed on the view:
    var buttonStyle: NT_LabelStyle {
        .iconOnly
    }
}
