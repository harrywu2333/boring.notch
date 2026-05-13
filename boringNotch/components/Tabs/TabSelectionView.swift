//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let allTabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Timer", icon: "timer", view: .pomodoro),
    TabModel(label: "Claude", icon: "terminal.fill", view: .claudeCode),
    TabModel(label: "Clipboard", icon: "clipboard.fill", view: .clipboard)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation

    var visibleTabs: [TabModel] {
        allTabs.filter { tab in
            if tab.view == .pomodoro { return Defaults[.showPomodoroTimer] }
            if tab.view == .claudeCode { return Defaults[.showClaudeCodeNotifier] }
            if tab.view == .clipboard { return Defaults[.showClipboardManager] }
            return true
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
