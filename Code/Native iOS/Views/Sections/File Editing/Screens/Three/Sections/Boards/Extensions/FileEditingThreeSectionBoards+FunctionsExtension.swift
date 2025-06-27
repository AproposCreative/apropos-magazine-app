//
//  FileEditingThreeSectionBoards+FunctionsExtension.swift
//  Native
//

import Foundation

extension FileEditingThreeSectionBoardsView {
    
    // MARK: - Functions:
    
    /// Returns the identifier of the given board:
    func identifier(_ board: NT_WhiteboardBoard) -> String {
        board.id
    }
    
    /// Returns the title of the given board:
    func title(_ board: NT_WhiteboardBoard) -> String {
        board.title
    }
    
    /// Returns the icon of the given board:
    func icon(_ board: NT_WhiteboardBoard) -> String {
        board.icon
    }
}
