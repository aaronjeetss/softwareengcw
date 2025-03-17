import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct GroupDetailView: View {
    let group: GroupModel
    @State private var selectedTab: GroupTab = .chores
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ChoresTabView(group: group)
                .tabItem { Label("Chores", systemImage: "checklist") }
                .tag(GroupTab.chores)
            PaymentsTabView(group: group)
                .tabItem { Label("Payments", systemImage: "creditcard") }
                .tag(GroupTab.payments)
        }
        .navigationTitle("Group Details")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if selectedTab == .chores {
                    NavigationLink(destination: CreateChoreView(group: group)) {
                        Image(systemName: "plus").font(.title2)
                    }
                } else if selectedTab == .payments {
                    NavigationLink(destination: CreatePaymentView(group: group)) {
                        Image(systemName: "plus").font(.title2)
                    }
                }
            }
        }
    }
}

struct ChoresTabView: View {
    let group: GroupModel
    @State private var chores: [Chore] = []
    @State private var message: String = ""
    @State private var selectedFilter: ChoreFilter = .all
    
    var filteredChores: [Chore] {
        switch selectedFilter {
        case .all:
            return chores
        case .week:
            if let weekInterval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) {
                return chores.filter { chore in
                    if let due = chore.dueDate {
                        return weekInterval.contains(due)
                    }
                    return false
                }
            }
            return []
        case .completed:
            return chores.filter { $0.completed }
        case .pastDeadline:
            return chores.filter { chore in
                if let due = chore.dueDate {
                    return due < Date() && !chore.completed
                }
                return false
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Group Code: \(group.code)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if !group.memberNames.isEmpty {
                            Text("Members: " + group.memberNames.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(ChoreFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    Text("Chores")
                        .font(.title2)
                        .bold()
                        .padding(.top, 10)
                    
                    if !message.isEmpty { Text(message).foregroundColor(.red) }
                    
                    ForEach(filteredChores) { chore in
                        HStack {
                            NavigationLink(destination: ChoreDetailView(chore: chore, group: group)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chore.title).font(.headline)
                                    if let due = chore.dueDate {
                                        Text("Due: \(due.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Text("Set by: \(chore.setBy)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("Assigned to: \(assignedName(for: chore.assignedTo))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button { toggleChoreCompletion(chore: chore) } label: {
                                Image(systemName: chore.completed ? "checkmark.circle.fill" : "checkmark.circle")
                                    .foregroundColor(chore.completed ? .green : .gray)
                                    .font(.title2)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                    }
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Chores")
            .onAppear { fetchChores() }
        }
    }
    
    private func assignedName(for uid: String) -> String {
        if let index = group.memberIDs.firstIndex(of: uid),
           group.memberNames.indices.contains(index) {
            return group.memberNames[index]
        }
        return uid
    }
    
    private func fetchChores() {
        let db = Firestore.firestore()
        db.collection("groups").document(group.id).collection("chores")
            .order(by: "createdAt")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    self.message = "Error fetching chores: \(error.localizedDescription)"
                    return
                }
                guard let docs = snapshot?.documents else { return }
                self.chores = docs.map { doc in
                    let data = doc.data()
                    let title = data["title"] as? String ?? ""
                    let description = data["description"] as? String ?? ""
                    let dueDate = (data["dueDate"] as? Timestamp)?.dateValue()
                    let repeatOption = data["repeat"] as? String ?? "Never"
                    let assignedTo = data["assignedTo"] as? String ?? ""
                    let setBy = data["setBy"] as? String ?? ""
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                    let completed = data["completed"] as? Bool ?? false
                    return Chore(id: doc.documentID,
                                 title: title,
                                 description: description,
                                 dueDate: dueDate,
                                 repeatOption: repeatOption,
                                 assignedTo: assignedTo,
                                 setBy: setBy,
                                 createdAt: createdAt,
                                 completed: completed)
                }
            }
    }
    
    private func toggleChoreCompletion(chore: Chore) {
        let db = Firestore.firestore()
        let newStatus = !chore.completed
        db.collection("groups").document(group.id).collection("chores").document(chore.id).updateData([
            "completed": newStatus
        ]) { error in
            if let error = error {
                self.message = "Error updating chore: \(error.localizedDescription)"
            } else {
                fetchChores()
            }
        }
    }
}

struct PaymentsTabView: View {
    let group: GroupModel
    @State private var payments: [Payment] = []
    @State private var message: String = ""
    @State private var selectedMemberIndex: Int = 0
    @State private var memberBalances: [String: Double] = [:]
    @State private var memberOwedBalances: [String: Double] = [:]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Group Code: \(group.code)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if !group.memberNames.isEmpty {
                            Text("Members: " + group.memberNames.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    
                    if !group.memberNames.isEmpty {
                        Picker("Select Person", selection: $selectedMemberIndex) {
                            ForEach(0..<group.memberNames.count, id: \.self) { index in
                                Text(group.memberNames[index]).tag(index)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                    }
                    
                    if group.memberIDs.indices.contains(selectedMemberIndex) {
                        let selectedUserID = group.memberIDs[selectedMemberIndex]
                        let owesYou = memberBalances[selectedUserID] ?? 0.0
                        let youOwe = memberOwedBalances[selectedUserID] ?? 0.0
                        let net = owesYou - youOwe
                        
                        VStack(spacing: 10) {
                            Text("\(group.memberNames[selectedMemberIndex]) owes you:")
                                .font(.headline)
                            Text("£\(String(format: "%.2f", owesYou))")
                                .font(.title)
                            
                            Text("You owe \(group.memberNames[selectedMemberIndex]):")
                                .font(.headline)
                            Text("£\(String(format: "%.2f", youOwe))")
                                .font(.title)
                            
                            Text("Net:")
                                .font(.headline)
                            if net > 0 {
                                Text("\(group.memberNames[selectedMemberIndex]) owes you £\(String(format: "%.2f", net))")
                                    .font(.largeTitle)
                                    .bold()
                            } else if net < 0 {
                                Text("You owe \(group.memberNames[selectedMemberIndex]) £\(String(format: "%.2f", abs(net)))")
                                    .font(.largeTitle)
                                    .bold()
                            } else {
                                Text("Settled")
                                    .font(.largeTitle)
                                    .bold()
                            }
                            
                            NavigationLink("View Details", destination: PaymentDetailsForPersonView(payments: paymentsBetween(with: selectedUserID), group: group, otherMemberName: group.memberNames[selectedMemberIndex], otherMemberID: selectedUserID))
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .padding()
                    }
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Payments")
            .onAppear { fetchPayments() }
        }
    }
    
    func paymentsBetween(with memberID: String) -> [Payment] {
        guard let currentUserID = Auth.auth().currentUser?.uid else { return [] }
        return payments.filter { payment in
            (payment.setByUid == currentUserID && (payment.shares[memberID]?.paid == false)) ||
            (payment.setByUid == memberID && (payment.shares[currentUserID]?.paid == false))
        }
    }
    
    func updateMemberBalances() {
        var owedToYou: [String: Double] = [:]
        var youOwe: [String: Double] = [:]
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        for payment in payments {
            if payment.setByUid == currentUserId {
                for (uid, share) in payment.shares {
                    if uid != currentUserId && share.paid == false {
                        owedToYou[uid, default: 0.0] += share.amount
                    }
                }
            } else {
                if let myShare = payment.shares[currentUserId], myShare.paid == false {
                    let creator = payment.setByUid
                    youOwe[creator, default: 0.0] += myShare.amount
                }
            }
        }
        self.memberBalances = owedToYou
        self.memberOwedBalances = youOwe
    }
    
    private func fetchPayments() {
        let db = Firestore.firestore()
        db.collection("groups").document(group.id).collection("payments")
            .order(by: "createdAt")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    self.message = "Error fetching payments: \(error.localizedDescription)"
                    return
                }
                guard let docs = snapshot?.documents else { return }
                self.payments = docs.map { doc in
                    let data = doc.data()
                    let itemName = data["itemName"] as? String ?? ""
                    let description = data["description"] as? String ?? ""
                    let totalAmount = data["amount"] as? Double ?? 0.0
                    let setByUid = data["setByUid"] as? String ?? ""
                    let setByName = data["setByName"] as? String ?? ""
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                    
                    var shares: [String: PaymentShare] = [:]
                    if let sharesData = data["shares"] as? [String: Any] {
                        for (uid, shareData) in sharesData {
                            if let shareMap = shareData as? [String: Any],
                               let amount = shareMap["amount"] as? Double,
                               let paid = shareMap["paid"] as? Bool {
                                shares[uid] = PaymentShare(amount: amount, paid: paid)
                            }
                        }
                    }
                    
                    return Payment(id: doc.documentID,
                                   itemName: itemName,
                                   description: description,
                                   totalAmount: totalAmount,
                                   setByUid: setByUid,
                                   setByName: setByName,
                                   createdAt: createdAt,
                                   shares: shares)
                }
                updateMemberBalances()
            }
    }
}
