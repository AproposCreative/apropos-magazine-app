//
//  SignInWithAppleButtonView.swift
//  Native
//

import SwiftUI
import AuthenticationServices

struct SignInWithAppleButtonView: View {
    
    // MARK: - Private properties:
    
    /// Label of the button:
    private let label: SignInWithAppleButton.Label
    
    /// Style of  the button:
    private let style: SignInWithAppleButton.Style
    
    /// Width of the button if applicable:
    private let width: CGFloat?
    
    /// Height of the button if applicable:
    private let height: CGFloat?
    
    /// Radius of the rounded corners of the button:
    private let cornerRadius: Double
    
    /// Style of the rounded corners of the button:
    private let cornerStyle: RoundedCornerStyle
    
    /// Vertical padding around the button:
    private let verticalPadding: Double
    
    /// Horizontal padding around the button:
    private let horizontalPadding: Double
    
    /// Method that gets called when the authorization is being requested:
    private let onRequest: (ASAuthorizationAppleIDRequest) -> ()
    
    /// Method that gets called when the authorization was completed:
    private let onCompletion: (Result<ASAuthorization, any Error>) -> ()
    
    init(
        label: SignInWithAppleButton.Label = .continue,
        style: SignInWithAppleButton.Style = .black,
        width: CGFloat? = nil,
        height: CGFloat? = 46,
        cornerRadius: Double = 14,
        cornerStyle: RoundedCornerStyle = .continuous,
        verticalPadding: Double = 0,
        horizontalPadding: Double = 0,
        onRequest: @escaping (ASAuthorizationAppleIDRequest) -> (),
        onCompletion: @escaping (Result<ASAuthorization, any Error>) -> ()
    ) {
        
        /// Properties initialization:
        self.label = label
        self.style = style
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.onRequest = onRequest
        self.onCompletion = onCompletion
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .signInWithAppleButtonStyle(style)
            .frame(
                width: width,
                height: height,
                alignment: .center
            )
            .roundedCorners(
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle
            )
            .padding(
                .vertical,
                verticalPadding
            )
            .padding(
                .horizontal,
                horizontalPadding
            )
    }
}

// MARK: - Item:

private extension SignInWithAppleButtonView {
    private var item: some View {
        SignInWithAppleButton(
            label,
            onRequest: onRequest,
            onCompletion: onCompletion
        )
    }
}

// MARK: - Preview:

#Preview {
    SignInWithAppleButtonView(
        label: .continue,
        style: .black,
        width: nil,
        height: 46,
        cornerRadius: 14,
        cornerStyle: .continuous,
        verticalPadding: 16,
        horizontalPadding: 16
    ) { request in
        
    } onCompletion: { result in
        
    }
}
