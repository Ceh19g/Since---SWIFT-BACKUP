import SwiftUI

struct PersistenceIssue: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String = "Changes Could Not Be Saved", error: Error) {
        self.title = title
        self.message = error.localizedDescription
    }
}

extension View {
    func persistenceIssueAlert(_ issue: Binding<PersistenceIssue?>) -> some View {
        alert(item: issue) { issue in
            Alert(
                title: Text(issue.title),
                message: Text(issue.message),
                dismissButton: .cancel(Text("OK"))
            )
        }
    }
}
