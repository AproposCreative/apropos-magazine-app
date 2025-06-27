//
//  FileEditingThreeBoardNote+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension FileEditingThreeBoardNoteView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the note is currently selected:
    var isSelected: Bool {
        
        /// Firstly checking whether or not we actually have the current location where the user has tapped:
        if let currentLocation {
            
            /// If yes, then getting the origin of the note that is based on its X-axis and Y-axis positions:
            let noteOrigin: CGPoint = .init(
                x: xAxisPosition,
                y: yAxisPosition
            )
            
            /// Then getting the size of the note that is based on the size of its frame:
            let noteSize: CGSize = .init(
                width: frame,
                height: frame
            )
            
            /// Then getting the rect of the note that is based on its origin and the size:
            let noteRect: CGRect = .init(
                origin: noteOrigin,
                size: noteSize
            )
            
            /// Then also getting the rect of the current location where the user has tapped that is based on an actual current location and the size of zero:
            let locationRect: CGRect = .init(
                origin: currentLocation,
                size: .zero
            )
            
            /// Then getting a 'Bool' value indicating whether or not the rect of the note is intersecting the rect of the current location where the user has tapped indicating whether or not the note should currently be selected:
            let isIntersecting: Bool = noteRect.intersects(locationRect)
            
            /// Finally returning a 'Bool' value indicating whether or not the rect of the note is intersecting the rect of the current location where the user has tapped indicating whether or not the note should currently be selected:
            return isIntersecting
        } else {
            
            /// If not, then simply returning 'false' indicating that the note isn't currently selected:
            return false
        }
    }
    
    /// Identifier of the note:
    var identifier: String {
        note.id
    }
    
    /// An actual text of the note:
    var text: String {
        note.text
    }
    
    /// Color of the note:
    var color: Color {
        note.color
    }
    
    /// Starting color of the gradient of the note:
    var gradientStart: Color {
        note.gradientStart
    }
    
    /// Ending color of the gradient of the note:
    var gradientEnd: Color {
        note.gradientEnd
    }
    
    /// Color of the background of the note:
    var backgroundColor: Color {
        color.opacity(backgroundOpacity)
    }
    
    /// Starting color of the background of the note:
    var backgroundGradientStart: Color {
        gradientStart.opacity(backgroundOpacity)
    }
    
    /// Ending color of the background of the note:
    var backgroundGradientEnd: Color {
        gradientEnd.opacity(backgroundOpacity)
    }
    
    /// Color of the shadow of the note:
    var shadowColor: Color {
        .black.opacity(0.08)
    }
    
    /// Font of the note:
    var font: Font {
        .system(
            size: 13,
            weight: .regular,
            design: .default
        )
    }
    
    /// Position of the note on the X-axis:
    var xAxisPosition: Double {
        note.xAxisPosition
    }
    
    /// Position of the note on the Y-axis:
    var yAxisPosition: Double {
        note.yAxisPosition
    }
    
    /// Radius of the rounded corners of the note:
    var cornerRadius: Double {
        16
    }
    
    /// Width of the border of the note:
    var borderWidth: Double {
        isSelected ? 2 : 0
    }
    
    // MARK: - Private computed properties:
    
    /// Opacity of the background of the note:
    private var backgroundOpacity: Double {
        0.16
    }
}
