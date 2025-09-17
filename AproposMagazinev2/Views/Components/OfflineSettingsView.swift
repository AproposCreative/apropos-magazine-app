import SwiftUI

struct OfflineSettingsView: View {
    @ObservedObject private var offlineManager = OfflineManager.shared
    @State private var showClearConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Offline indstillinger")
                .font(.headline)
            
            VStack(spacing: 12) {
                // Connection Status
                HStack {
                    Image(systemName: offlineManager.isOnline ? "wifi" : "wifi.slash")
                        .foregroundColor(offlineManager.isOnline ? .green : .red)
                    
                    Text(offlineManager.isOnline ? "Online" : "Offline")
                        .font(.subheadline)
                    
                    Spacer()
                    
                    if offlineManager.syncInProgress {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                
                Divider()
                
                // Storage Info
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Offline artikler")
                            .font(.subheadline)
                        Text("\(offlineManager.getOfflineArticles().count) artikler")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Lagerplads")
                            .font(.subheadline)
                        Text(offlineManager.getOfflineStorageSize())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Last Sync
                if let lastSync = offlineManager.lastSyncDate {
                    HStack {
                        Text("Sidste sync")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Text(lastSync, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Actions
                HStack(spacing: 12) {
                    Button(action: {
                        offlineManager.syncWhenOnline()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Sync nu")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                    .disabled(!offlineManager.isOnline || offlineManager.syncInProgress)
                    
                    Spacer()
                    
                    Button(action: {
                        showClearConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Ryd cache")
                        }
                        .font(.subheadline)
                        .foregroundColor(.red)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .alert("Ryd offline cache", isPresented: $showClearConfirmation) {
            Button("Annuller", role: .cancel) { }
            Button("Ryd", role: .destructive) {
                offlineManager.clearOfflineStorage()
            }
        } message: {
            Text("Dette vil slette alle offline gemte artikler. Er du sikker?")
        }
    }
}
