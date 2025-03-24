import SwiftUI
import FirebaseAuth
import FirebaseFirestore

func generateGroupCode(length: Int = 6) -> String {
    let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return String((0..<length).compactMap { _ in chars.randomElement() })
}

enum Route: Hashable {
    case signUp
}

struct GroupModel: Identifiable, Hashable {
    let id: String
    let code: String
    let ownerId: String
    let memberIDs: [String]
    var memberNames: [String] = []
}

struct Chore: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let dueDate: Date?
    let repeatOption: String
    let assignedTo: String
    let setBy: String
    let createdAt: Date?
    var completed: Bool
}

struct PaymentShare: Codable, Hashable {
    var amount: Double
    var paid: Bool
}

struct Payment: Identifiable, Hashable {
    let id: String
    let itemName: String
    let description: String
    let totalAmount: Double
    let setByUid: String
    let setByName: String
    let createdAt: Date?
    var shares: [String: PaymentShare]
}

enum ChoreFilter: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }
    case all = "All"
    case week = "Due This Week"
    case completed = "Completed"
    case pastDeadline = "Past Deadline"
}

enum GroupTab: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }
    case chores = "Chores"
    case payments = "Payments"
}

struct PaymentDetailsForPersonView: View {
    let payments: [Payment]
    let group: GroupModel
    let otherMemberName: String
    let otherMemberID: String
    @State private var message: String = ""
    let currentUserID = Auth.auth().currentUser?.uid ?? ""
    
    var paymentsTheyOweYou: [Payment] {
        payments.filter { payment in
            payment.setByUid == currentUserID && // I set it
            payment.shares.keys.contains(otherMemberID) && // They owe something
            (payment.shares[otherMemberID]?.paid == false) // Not paid yet
        }
    }
    
    var paymentsYouOweThem: [Payment] {
        payments.filter { payment in
            payment.setByUid == otherMemberID && // They set it
            payment.shares.keys.contains(currentUserID) && // I owe something
            (payment.shares[currentUserID]?.paid == false) // Not paid yet
        }
    }
    
    var body: some View {
        List {
            if !paymentsTheyOweYou.isEmpty {
                Section(header: Text("\(otherMemberName) owes you")) {
                    ForEach(paymentsTheyOweYou) { payment in
                        PaymentRow(payment: payment, group: group, otherMemberID: otherMemberID, currentUserID: currentUserID)
                    }
                }
            }
            if !paymentsYouOweThem.isEmpty {
                Section(header: Text("You owe \(otherMemberName)")) {
                    ForEach(paymentsYouOweThem) { payment in
                        PaymentRow(payment: payment, group: group, otherMemberID: otherMemberID, currentUserID: currentUserID)
                    }
                }
            }
            if paymentsTheyOweYou.isEmpty && paymentsYouOweThem.isEmpty {
                Text("No outstanding payments between you and \(otherMemberName).")
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("\(otherMemberName) - Payment Details")
    }
}

struct PaymentRow: View {
    let payment: Payment
    let group: GroupModel
    let otherMemberID: String
    let currentUserID: String
    @State private var message: String = ""
    
    var share: PaymentShare? {
        if payment.setByUid == currentUserID {
            return payment.shares[otherMemberID]
        } else if payment.setByUid == otherMemberID {
            return payment.shares[currentUserID]
        }
        return nil
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(payment.itemName)
                    .font(.headline)
                if let share = share {
                    Text("Amount: £\(String(format: "%.2f", share.amount))")
                        .font(.subheadline)
                }
            }
            Spacer()
            if let share = share {
                Button(action: {
                    togglePaidStatus(currentStatus: share.paid)
                }) {
                    Image(systemName: share.paid ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundColor(share.paid ? .green : .gray)
                        .font(.title2)
                }
            }
        }
        .padding(.vertical, 4)
        if !message.isEmpty {
            Text(message).foregroundColor(.red).font(.caption)
        }
    }
    
    func togglePaidStatus(currentStatus: Bool) {
        let newStatus = !currentStatus
        var targetUID = ""
        if payment.setByUid == currentUserID {
            targetUID = otherMemberID
        } else if payment.setByUid == otherMemberID {
            targetUID = currentUserID
        }
        
        let db = Firestore.firestore()
        db.collection("groups").document(group.id).collection("payments").document(payment.id).updateData([
            "shares.\(targetUID).paid": newStatus
        ]) { error in
            if let error = error {
                message = "Error updating share: \(error.localizedDescription)"
            }
        }
    }
}

struct PaymentDetailView: View {
    let payment: Payment
    let group: GroupModel
    @State private var message: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(payment.itemName)
                .font(.largeTitle)
                .bold()
            Text("Description:")
                .font(.headline)
            Text(payment.description)
                .font(.body)
            Text("Total Amount: £\(String(format: "%.2f", payment.totalAmount))")
            Text("Set By: \(memberName(for: payment.setByUid))")
            Text("Assigned To:")
                .font(.headline)
            ForEach(Array(payment.shares.keys), id: \.self) { uid in
                HStack {
                    Text(memberName(for: uid))
                    Spacer()
                    if let share = payment.shares[uid] {
                        Text("£\(String(format: "%.2f", share.amount))")
                        Button(action: {
                            toggleSharePaid(for: uid, currentPaid: share.paid)
                        }) {
                            Image(systemName: share.paid ? "checkmark.circle.fill" : "checkmark.circle")
                                .foregroundColor(share.paid ? .green : .gray)
                                .font(.title2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            if !message.isEmpty {
                Text(message)
                    .foregroundColor(.red)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Payment Details")
    }
    
    private func memberName(for uid: String) -> String {
        if let index = group.memberIDs.firstIndex(of: uid),
           group.memberNames.indices.contains(index) {
            return group.memberNames[index]
        }
        return uid
    }
    
    private func toggleSharePaid(for uid: String, currentPaid: Bool) {
        let newPaid = !currentPaid
        let db = Firestore.firestore()
        db.collection("groups").document(group.id).collection("payments").document(payment.id).updateData([
            "shares.\(uid).paid": newPaid
        ]) { error in
            if let error = error {
                message = "Error updating share: \(error.localizedDescription)"
            }
        }
    }
}

struct CreatePaymentView: View {
    let group: GroupModel
    @State private var itemName: String = ""
    @State private var description: String = ""
    @State private var amount: String = "0.0"
    @State private var selectedMemberIndices: Set<Int> = []
    @State private var splitEqually: Bool = true
    @State private var customShares: [Int: String] = [:]
    @State private var setByUid: String = ""
    @State private var setByName: String = ""
    @State private var message: String = ""
    
    var body: some View {
        Form {
            Section(header: Text("Payment Details")) {
                TextField("Item Name", text: $itemName)
                TextEditor(text: $description)
                    .frame(height: 100)
                TextField("Total Amount (e.g. 10.50)", text: $amount)
                    .keyboardType(.decimalPad)
            }
            
            Section(header: Text("Split With")) {
                if group.memberNames.isEmpty {
                    Text("No members available")
                } else {
                    ForEach(group.memberNames.indices, id: \.self) { idx in
                        let name = group.memberNames[idx]
                        HStack {
                            Text(name)
                            Spacer()
                            if selectedMemberIndices.contains(idx) {
                                Image(systemName: "checkmark")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedMemberIndices.contains(idx) {
                                selectedMemberIndices.remove(idx)
                                customShares.removeValue(forKey: idx)
                            } else {
                                selectedMemberIndices.insert(idx)
                            }
                        }
                    }
                }
                Toggle("Split Equally", isOn: $splitEqually)
                if !splitEqually {
                    ForEach(selectedMemberIndices.sorted(), id: \.self) { idx in
                        HStack {
                            Text(group.memberNames[idx])
                            TextField("Share Amount", text: Binding(
                                get: { customShares[idx] ?? "" },
                                set: { customShares[idx] = $0 }
                            ))
                            .keyboardType(.decimalPad)
                        }
                    }
                }
                Text("Set By: \(setByName)")
            }
            
            if !message.isEmpty {
                Section {
                    Text(message)
                        .foregroundColor(.red)
                }
            }
            
            Section {
                Button("Create Payment") {
                    createPayment()
                }
            }
        }
        .navigationTitle("Create Payment")
        .onAppear { fetchCurrentUserName() }
    }
    
    private func fetchCurrentUserName() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        db.collection("users").document(uid).getDocument { doc, error in
            if let doc = doc, doc.exists {
                let data = doc.data()
                let firstName = data?["firstName"] as? String ?? ""
                let lastName = data?["lastName"] as? String ?? ""
                DispatchQueue.main.async {
                    setByUid = uid
                    setByName = "\(firstName) \(lastName)"
                }
            }
        }
    }
    
    private func createPayment() {
        guard !itemName.trimmingCharacters(in: .whitespaces).isEmpty else {
            message = "Item name is required."
            return
        }
        guard let totalAmount = Double(amount) else {
            message = "Please enter a valid total amount."
            return
        }
        guard !selectedMemberIndices.isEmpty else {
            message = "Please select at least one member to split with."
            return
        }
        
        var shares: [String: [String: Any]] = [:]
        let db = Firestore.firestore()
        let selectedUIDs = selectedMemberIndices.compactMap { idx -> String? in
            if group.memberIDs.indices.contains(idx) {
                return group.memberIDs[idx]
            }
            return nil
        }
        if splitEqually {
            let equalShare = totalAmount / Double(selectedUIDs.count)
            for uid in selectedUIDs {
                shares[uid] = ["amount": equalShare, "paid": false]
            }
        } else {
            var sum: Double = 0.0
            for idx in selectedMemberIndices {
                if let shareStr = customShares[idx], let shareVal = Double(shareStr) {
                    sum += shareVal
                } else {
                    message = "Please enter valid share amounts for all selected members."
                    return
                }
            }
            if abs(sum - totalAmount) > 0.01 {
                message = "The sum of shares (£\(String(format: "%.2f", sum))) does not equal the total amount (£\(String(format: "%.2f", totalAmount)))."
                return
            }
            for idx in selectedMemberIndices {
                if let shareStr = customShares[idx], let shareVal = Double(shareStr) {
                    if group.memberIDs.indices.contains(idx) {
                        let uid = group.memberIDs[idx]
                        shares[uid] = ["amount": shareVal, "paid": false]
                    }
                }
            }
        }
        
        let paymentData: [String: Any] = [
            "itemName": itemName,
            "description": description,
            "amount": totalAmount,
            "shares": shares,
            "setByUid": setByUid,
            "setByName": setByName,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        db.collection("groups").document(group.id).collection("payments").addDocument(data: paymentData) { error in
            if let error = error {
                message = "Error creating payment: \(error.localizedDescription)"
            } else {
                message = "Payment created successfully!"
            }
        }
    }
}

struct ChoreDetailView: View {
    let chore: Chore
    let group: GroupModel
    @State private var message: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(chore.title)
                .font(.largeTitle)
                .bold()
            Text("Description:")
                .font(.headline)
            Text(chore.description)
                .font(.body)
            if let due = chore.dueDate {
                Text("Due Date: \(due.formatted(date: .abbreviated, time: .omitted))")
            }
            Text("Repeat: \(chore.repeatOption)")
            Text("Assigned To: \(assignedName(for: chore.assignedTo))")
            Text("Set By: \(chore.setBy)")
            if chore.completed {
                Text("Status: Completed")
                    .foregroundColor(.green)
                    .bold()
            } else {
                Button("Mark as Complete") { markChoreComplete() }
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            if !message.isEmpty { Text(message).foregroundColor(.red) }
            Spacer()
        }
        .padding()
        .navigationTitle("Chore Details")
    }
    
    private func assignedName(for uid: String) -> String {
        if let index = group.memberIDs.firstIndex(of: uid),
           group.memberNames.indices.contains(index) {
            return group.memberNames[index]
        }
        return uid
    }
    
    private func markChoreComplete() {
        let db = Firestore.firestore()
        db.collection("groups").document(group.id).collection("chores").document(chore.id).updateData([
            "completed": true
        ]) { error in
            if let error = error {
                message = "Error marking as complete: \(error.localizedDescription)"
            }
        }
    }
}

struct CreateChoreView: View {
    let group: GroupModel
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var dueDate: Date = Date()
    @State private var repeatOption: String = "Never"
    @State private var assignedToIndex: Int = 0
    @State private var setBy: String = ""
    @State private var message: String = ""
    
    let repeatOptions = ["Never", "Daily", "Weekly", "Monthly"]
    
    var body: some View {
        Form {
            Section(header: Text("Chore Details")) {
                TextField("Chore Name", text: $title)
                TextEditor(text: $description).frame(height: 100)
            }
            Section(header: Text("Schedule")) {
                DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                Picker("Repeat", selection: $repeatOption) {
                    ForEach(repeatOptions, id: \.self) { option in Text(option) }
                }
            }
            Section(header: Text("Assignment")) {
                if group.memberNames.isEmpty {
                    Text("No members available")
                } else {
                    Picker("Assigned To", selection: $assignedToIndex) {
                        ForEach(0..<group.memberNames.count, id: \.self) { index in
                            Text(group.memberNames[index])
                        }
                    }
                }
                Text("Set By: \(setBy)")
            }
            if !message.isEmpty {
                Section { Text(message).foregroundColor(.red) }
            }
            Section {
                Button("Create Chore") { createChore() }
            }
        }
        .navigationTitle("Create Chore")
        .onAppear { fetchCurrentUserName() }
    }
    
    private func fetchCurrentUserName() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        db.collection("users").document(uid).getDocument { doc, error in
            if let doc = doc, doc.exists {
                let data = doc.data()
                let firstName = data?["firstName"] as? String ?? ""
                let lastName = data?["lastName"] as? String ?? ""
                DispatchQueue.main.async { setBy = "\(firstName) \(lastName)" }
            }
        }
    }
    
    private func createChore() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            message = "Chore name is required."
            return
        }
        let assignedTo: String = group.memberIDs.indices.contains(assignedToIndex) ? group.memberIDs[assignedToIndex] : ""
        let db = Firestore.firestore()
        let choreData: [String: Any] = [
            "title": title,
            "description": description,
            "dueDate": Timestamp(date: dueDate),
            "repeat": repeatOption,
            "assignedTo": assignedTo,
            "setBy": setBy,
            "createdAt": FieldValue.serverTimestamp(),
            "completed": false
        ]
        db.collection("groups").document(group.id).collection("chores").addDocument(data: choreData) { error in
            if let error = error {
                message = "Error creating chore: \(error.localizedDescription)"
            } else {
                message = "Chore created successfully!"
            }
        }
    }
}

#Preview {
    ContentView()
}
