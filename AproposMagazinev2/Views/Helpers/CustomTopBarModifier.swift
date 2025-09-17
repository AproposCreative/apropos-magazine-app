import SwiftUI

struct CustomTopBarModifier: ViewModifier {
    @Environment(\.presentationMode) var presentationMode
    
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.primary)
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    LogoView()
                        .frame(height: 32)
                }
            }
            .toolbarBackground(
                .ultraThinMaterial,
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
    }
    
    @Environment(\.colorScheme) private var colorScheme
}

extension View {
    func customTopBar() -> some View {
        self.modifier(CustomTopBarModifier())
    }
} 