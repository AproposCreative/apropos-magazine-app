//
//  HapticFeedbacks.swift
//  Native
//

import SwiftUI

@MainActor
struct HapticFeedbacks {
    
    // MARK: - Functions:
    
    /// Feedback that triggers after any successful action if enabled:
    static func success(isEnabled: Bool = true) {
        
        /// Firstly making sure that the haptic feedbacks are actually enabled:
        guard isEnabled else { return }
        
        /// If yes, then triggering the success feedback:
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    /// Feedback that triggers when there is an error if enabled:
    static func error(isEnabled: Bool = true) {
        
        /// Firstly making sure that the haptic feedbacks are actually enabled:
        guard isEnabled else { return }
        
        /// If yes, then triggering the error feedback:
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    
    /// Soft feedback that is usually used when deleting or hiding something within the app if enabled:
    static func soft(isEnabled: Bool = true) {
        
        /// Firstly making sure that the haptic feedbacks are actually enabled:
        guard isEnabled else { return }
        
        /// If yes, then triggering the soft feedback:
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
    
    /// Feedback that triggers when the selection changed if enabled:
    static func selectionChanged(isEnabled: Bool = true) {
        
        /// Firstly making sure that the haptic feedbacks are actually enabled:
        guard isEnabled else { return }
        
        /// If yes, then triggering the selection changed feedback:
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
