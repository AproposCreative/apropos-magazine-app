//
//  FileEditingThreeBoard+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension FileEditingThreeBoardView {
    
    // MARK: - Functions:
    
    /// Lets the user add a new text to the canvas:
    func newText() {
        
        /*
         
         NOTE: You can add your own logic for adding a new text here.
         
         */
        
    }
    
    /// Lets the user add a new note to the canvas:
    func newNote() {
        
        /*
         
         NOTE: You can add your own logic for adding a new note here.
         
         */
        
    }
    
    /// Lets the user add a new shape to the canvas:
    func newShape() {
        
        /*
         
         NOTE: You can add your own logic for adding a new shape here.
         
         */
        
    }
    
    /// Lets the user add a new image to the canvas:
    func newImage() {
        
        /*
         
         NOTE: You can add your own logic for adding a new image here.
         
         */
        
    }
    
    /// Lets the user add a new connection between the elements on the canvas:
    func newConnection() {
        
        /*
         
         NOTE: You can add your own logic for adding a new connection here.
         
         */
        
    }
    
    /// Lets the user share the board with others:
    func share() {
        
        /*
         
         NOTE: You can add your own logic for sharing here.
         
         */
        
    }
}

// MARK: - Canvas:

extension FileEditingThreeBoardView {
    
    // MARK: - Functions:
    
    /// Returns the width of the canvas that is based on the given proxy, as well as the notes:
    func canvasWidth(forProxy proxy: GeometryProxy) -> Double {
        
        /// Firstly getting the width of the entire view that is based on the given proxy:
        let width: Double = width(forProxy: proxy)
        
        /// Then getting the maximum position of the notes on the X-axis:
        let maximumXAxisPosition: Double = notes.map { $0.xAxisPosition }.max() ?? 0
        
        /// Then getting the width of all of the notes by adding the frame of each of the notes, as well as the padding of the notes to the maximum position of the notes on the X-axis:
        let allNotesWidth: Double = isNotesEmpty ? 0 : maximumXAxisPosition + noteFrame + notesPadding
        
        /// Lastly getting the width of the canvas that is based on whether or not the width of all of the notes is larger then the width of the entire view:
        let canvasWidth: Double = allNotesWidth > width ? allNotesWidth : width
        
        /// Finally returning the width of the canvas:
        return canvasWidth
    }
    
    /// Returns the height of the canvas that is based on the given proxy, as well as the notes:
    func canvasHeight(forProxy proxy: GeometryProxy) -> Double {
        
        /// Firstly getting the height of the entire view that is based on the given proxy:
        let height: Double = height(forProxy: proxy)
        
        /// Then getting the maximum position of the notes on the Y-axis:
        let maximumYAxisPosition: Double = notes.map { $0.yAxisPosition }.max() ?? 0
        
        /// Then getting the height of all of the notes by adding the frame of each of the notes, as well as the padding of the notes to the maximum position of the notes on the Y-axis:
        let allNotesHeight: Double = isNotesEmpty ? 0 : maximumYAxisPosition + noteFrame + notesPadding
        
        /// Lastly getting the height of the canvas that is based on whether or not the height of all of the notes is larger then the height of the entire view:
        let canvasHeight: Double = allNotesHeight > height ? allNotesHeight : height
        
        /// Finally returning the height of the canvas:
        return canvasHeight
    }
    
    /// Displays the content in the canvas using the given context and the size provided:
    func canvasRenderer(
        withContext context: inout GraphicsContext,
        ofSize size: CGSize
    ) {
        
        /// Firstly iterating through an array of all of the notes:
        for note in notes {
            
            /// Then making sure that we have the content of the given note:
            if let noteContent: GraphicsContext.ResolvedSymbol = context.resolveSymbol(id: note.id) {
                
                /// If yes, then getting the rect of the given note to display its content in:
                let noteRect: CGRect = .init(
                    origin: .init(
                        x: note.xAxisPosition,
                        y: note.yAxisPosition
                    ),
                    size: noteContent.size
                )
                
                /// Lastly drawing the content of the note in the given rect:
                context.draw(
                    noteContent,
                    in: noteRect
                )
            }
        }
    }
    
    /// Updates the current location where the user has tapped on the canvas with the given value:
    func updateCurrenLocation(_ location: CGPoint) {
        
        /// Firstly making sure that the current location isn't the same as the given value:
        if currentLocation != location {
            
            /// If yes, then updating the current location with the given value:
            currentLocation = location
        }
    }
    
    // MARK: - Private functions:
    
    /// Returns the width that is based on the given proxy:
    private func width(forProxy proxy: GeometryProxy) -> Double {
        proxy.size.width
    }
    
    /// Returns the height that is based on the given proxy:
    private func height(forProxy proxy: GeometryProxy) -> Double {
        proxy.size.height
    }
}
