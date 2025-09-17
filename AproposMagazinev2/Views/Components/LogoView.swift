import SwiftUI

struct LogoView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Image(colorScheme == .dark ? "AproposLogoWhite" : "AproposLogoBlack")
            .resizable()
            .scaledToFit()
            .frame(height: 30)
    }
}

struct LogoView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            LogoView()
                .preferredColorScheme(.light)
            
            LogoView()
                .preferredColorScheme(.dark)
        }
        .padding()
    }
}
