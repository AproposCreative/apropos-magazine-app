//
//  FileEditingThreeBoards+FunctionsExtension.swift
//  Native
//

import Foundation

extension FileEditingThreeBoardsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given board:
    func title(_ board: NT_WhiteboardBoard) -> String {
        board.title
    }
    
    /// Returns the icon of the given board:
    func icon(_ board: NT_WhiteboardBoard) -> String {
        board.icon
    }
}
