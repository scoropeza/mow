//
//  ContentViewPlaceholder.swift
//  mow
//
//  Shared placeholder layout for Settings, Model Management, Logs.
//

import SwiftUI

struct ContentViewPlaceholder: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .frame(minWidth: 320, minHeight: 160)
        .padding(24)
    }
}
