//
//  FileEditingThreeBoardNoteView.swift
//  Native
//

import SwiftUI

struct FileEditingThreeBoardNoteView: View {
    
    // MARK: - Properties:
    
    /// An actual note to display:
    let note: NT_WhiteboardNote
    
    /// Size of the frame of the note:
    let frame: Double
    
    /// Current location where the user has tapped on the canvas if applicable:
    let currentLocation: CGPoint?
    
    init(
        note: NT_WhiteboardNote,
        frame: Double,
        currentLocation: CGPoint?
    ) {
        
        /// Properties initialization:
        self.note = note
        self.frame = frame
        self.currentLocation = currentLocation
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        Text(text)
            .font(font)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
            .padding(12)
            .frame(
                width: frame,
                height: frame,
                alignment: .topLeading
            )
            .background(background)
            .roundedCorners(
                cornerRadius: cornerRadius,
                cornerStyle: .continuous
            )
            .shadow(
                color: shadowColor,
                radius: 8,
                x: 0,
                y: 4
            )
            .overlay(selected)
            .tag(identifier)
            .animation(
                .default,
                value: isSelected
            )
    }
}

// MARK: - Background:

private extension FileEditingThreeBoardNoteView {
    private var background: some View {
        ZStack {
            backgroundContent
        }
    }
    
    @ViewBuilder
    private var backgroundContent: some View {
        Color(.systemBackground)
        backgroundItem
    }
    
    private var backgroundItem: some View {
        LinearGradient(
            colors: [
                backgroundGradientStart,
                backgroundGradientEnd
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Selected:

private extension FileEditingThreeBoardNoteView {
    private var selected: some View {
        RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )
        .gradientBorder(
            width: borderWidth,
            color: color,
            gradientStart: gradientStart,
            gradientEnd: gradientEnd,
            isGradient: true
        )
    }
}

// MARK: - Preview:

#Preview {
    FileEditingThreeBoardNoteView(
        note: .example.first!,
        frame: 200,
        currentLocation: nil
    )
    .padding()
}
